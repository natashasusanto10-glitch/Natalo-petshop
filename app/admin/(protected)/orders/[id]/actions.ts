"use server";

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { createBiteshipShipment } from "@/lib/biteship";
import { sendOrderStatusEmail } from "@/lib/email-order";
import { assertCanTransitionOrderStatus, transitionOrderStatus } from "@/lib/order-transitions";
import { buildOrderDetailUrl } from "@/lib/order-detail";
import { sendOrderStatusPush } from "@/lib/push";
import { SELF_PICKUP_METHOD, createPickupCode } from "@/lib/self-pickup";
import {
  sendCustomMessage,
  sendOrderCancelled,
  sendOrderCompleted,
  sendOrderShipped,
  sendPaymentConfirmed,
} from "@/lib/whatsapp";

/**
 * Guard semua admin server action. Layout (protected) hanya melindungi page render,
 * tapi server action bisa di-invoke langsung lewat POST. Tanpa check ini, customer
 * bisa eksekusi action admin (mark paid, cancel, dll) kalau tahu endpoint-nya.
 */
async function requireAdmin() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    throw new Error("Akses ditolak. Hanya admin yang bisa mengubah order.");
  }
  return session;
}

function revalidateOrderAdmin(orderId: string) {
  revalidatePath(`/admin/orders/${orderId}`);
  revalidatePath("/admin/orders");
  revalidatePath("/admin");
  revalidatePath("/admin/dashboard");
}

async function getEmailContext(orderId: string) {
  return prisma.order.findUnique({
    where: { id: orderId },
    select: {
      orderNumber: true,
      trackingToken: true,
      customerName: true,
      customerPhone: true,
      customerEmail: true,
      total: true,
      trackingNumber: true,
      courierCode: true,
      courierService: true,
      paymentUrl: true,
    },
  });
}

export async function markAsPaid(orderId: string) {
  await requireAdmin();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true, paymentStatus: true, orderType: true },
  });
  if (!current) return;

  if (current.status === "CANCELLED" || current.status === "REFUNDED") {
    throw new Error(
      `Tidak bisa konfirmasi pembayaran: order sudah ${
        current.status === "CANCELLED" ? "dibatalkan" : "di-refund"
      }.`
    );
  }

  if (current.paymentStatus === "PAID") {
    throw new Error("Pembayaran sudah dikonfirmasi sebelumnya.");
  }
  if (current.paymentStatus === "REFUNDED") {
    throw new Error("Pembayaran sudah di-refund, tidak bisa di-mark PAID.");
  }

  const result = await prisma.order.updateMany({
    where: {
      id: orderId,
      status: { notIn: ["CANCELLED", "REFUNDED"] },
      paymentStatus: { notIn: ["PAID", "REFUNDED"] },
    },
    data:
      current.status === "PENDING" && current.orderType === SELF_PICKUP_METHOD
        ? { paymentStatus: "PAID", status: "PROCESSING", pickupStatus: "PREPARING" }
        : current.status === "PENDING"
        ? { paymentStatus: "PAID", status: "PAID" }
        : current.orderType === SELF_PICKUP_METHOD
        ? { paymentStatus: "PAID", pickupStatus: "PREPARING" }
        : { paymentStatus: "PAID" },
  });
  if (result.count === 0) {
    throw new Error("Order sudah berubah, refresh halaman dulu.");
  }

  const ctx = await getEmailContext(orderId);
  if (ctx) {
    await sendOrderStatusEmail("PAID", ctx).catch(() => {});
    await sendOrderStatusPush(orderId, ctx.orderNumber, "PAID").catch(() => {});
    sendPaymentConfirmed(ctx).catch((error) => {
      console.error("[whatsapp] payment confirmed notification failed", error);
    });
  }

  if (current.orderType !== SELF_PICKUP_METHOD) {
    await createBiteshipShipment(orderId).catch((error) => {
      console.error("[biteship] create shipment after manual payment failed", error);
    });
  }
  revalidateOrderAdmin(orderId);
}

export async function createShipment(orderId: string) {
  await requireAdmin();
  await createBiteshipShipment(orderId);
  revalidateOrderAdmin(orderId);
}

export async function markAsProcessing(orderId: string) {
  await requireAdmin();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true, paymentStatus: true },
  });
  if (!current) return;
  if (current.paymentStatus !== "PAID") {
    throw new Error("Order belum lunas, belum bisa mulai packing.");
  }

  await transitionOrderStatus(orderId, "PROCESSING");
  const ctx = await getEmailContext(orderId);
  if (ctx) {
    await sendOrderStatusPush(orderId, ctx.orderNumber, "PROCESSING").catch(() => {});
    sendCustomMessage(
      ctx.customerPhone,
      `Halo ${ctx.customerName}, pesanan ${ctx.orderNumber} sedang kami proses. Detail pesanan: ${buildOrderDetailUrl(ctx.orderNumber, ctx.trackingToken)}`
    ).catch((error) => {
      console.error("[whatsapp] order processing notification failed", error);
    });
  }
  revalidateOrderAdmin(orderId);
}

export async function markAsShipped(orderId: string, formData: FormData) {
  await requireAdmin();
  const trackingNumber = String(formData.get("trackingNumber") || "").trim();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true },
  });
  if (!current) return;

  let didTransition = false;

  if (current.status !== "SHIPPED") {
    await transitionOrderStatus(orderId, "SHIPPED", {
      trackingNumber: trackingNumber || null,
    });
    didTransition = true;
  } else {
    await prisma.order.updateMany({
      where: { id: orderId, status: "SHIPPED" },
      data: { trackingNumber: trackingNumber || null },
    });
  }

  if (didTransition) {
    const ctx = await getEmailContext(orderId);
    if (ctx) {
      await sendOrderStatusEmail("SHIPPED", ctx).catch(() => {});
      await sendOrderStatusPush(orderId, ctx.orderNumber, "SHIPPED").catch(() => {});
      sendOrderShipped(ctx).catch((error) => {
        console.error("[whatsapp] order shipped notification failed", error);
      });
    }
  }

  revalidateOrderAdmin(orderId);
}

export async function markAsDelivered(orderId: string) {
  await requireAdmin();
  await transitionOrderStatus(orderId, "DELIVERED");
  const ctx = await getEmailContext(orderId);
  if (ctx) {
    await sendOrderStatusEmail("DELIVERED", ctx).catch(() => {});
    await sendOrderStatusPush(orderId, ctx.orderNumber, "DELIVERED").catch(() => {});
    sendOrderCompleted(ctx).catch((error) => {
      console.error("[whatsapp] order completed notification failed", error);
    });
  }
  revalidateOrderAdmin(orderId);
}

export async function markAsReadyForPickup(orderId: string) {
  await requireAdmin();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      status: true,
      paymentStatus: true,
      orderType: true,
      pickupCode: true,
      orderNumber: true,
    },
  });
  if (!current) return;
  if (current.orderType !== SELF_PICKUP_METHOD) {
    throw new Error("Order ini bukan Self Pick Up.");
  }
  if (current.paymentStatus !== "PAID") {
    throw new Error("Order belum lunas, belum bisa ditandai siap diambil.");
  }

  let pickupCode = current.pickupCode;
  if (!pickupCode) {
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const candidate = createPickupCode();
      const exists = await prisma.order.findUnique({
        where: { pickupCode: candidate },
        select: { id: true },
      });
      if (!exists) {
        pickupCode = candidate;
        break;
      }
    }
  }
  if (!pickupCode) throw new Error("Gagal membuat kode pickup.");

  await transitionOrderStatus(orderId, "READY_FOR_PICKUP", {
    pickupCode,
    pickupStatus: "READY",
    readyForPickupAt: new Date(),
  });

  await sendOrderStatusPush(orderId, current.orderNumber, "READY_FOR_PICKUP").catch(() => {});
  revalidateOrderAdmin(orderId);
}

export async function markAsPickedUp(orderId: string) {
  const admin = await requireAdmin();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true, paymentStatus: true, orderType: true, pickupStatus: true },
  });
  if (!current) return;
  if (current.orderType !== SELF_PICKUP_METHOD) {
    throw new Error("Order ini bukan Self Pick Up.");
  }
  if (current.status !== "READY_FOR_PICKUP" || current.paymentStatus !== "PAID") {
    throw new Error("Order belum siap untuk diserahkan.");
  }
  if (current.pickupStatus === "PICKED_UP") {
    throw new Error("Order sudah pernah diserahkan.");
  }

  await transitionOrderStatus(orderId, "DELIVERED", {
    pickupStatus: "PICKED_UP",
    pickedUpAt: new Date(),
    pickedUpByAdminId: admin.sub,
  });
  revalidateOrderAdmin(orderId);
}

export async function markAsCancelled(orderId: string) {
  await requireAdmin();
  const variantProductIdsToSync = new Set<string>();
  const nonVariantProductIdsToSync = new Set<string>();
  let didCancel = false;

  await prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({
      where: { id: orderId },
      include: { items: true },
    });
    if (!order || order.status === "CANCELLED") return;
    assertCanTransitionOrderStatus(order.status, "CANCELLED");

    const shouldRestoreStock =
      order.status === "PENDING" ||
      order.status === "PAID" ||
      order.status === "PROCESSING";

    if (shouldRestoreStock) {
      for (const item of order.items) {
        if (item.variantId) {
          await tx.productVariant.updateMany({
            where: { id: item.variantId },
            data: { stock: { increment: item.quantity } },
          });
          variantProductIdsToSync.add(item.productId);
        } else {
          await tx.product.updateMany({
            where: { id: item.productId },
            data: { stock: { increment: item.quantity } },
          });
          nonVariantProductIdsToSync.add(item.productId);
        }
      }

      for (const pid of variantProductIdsToSync) {
        const agg = await tx.productVariant.aggregate({
          where: { productId: pid, deletedAt: null, isActive: true },
          _sum: { stock: true },
        });
        await tx.product.update({
          where: { id: pid },
          data: { stock: agg._sum.stock ?? 0 },
        });
      }
    }

    const result = await tx.order.updateMany({
      where: { id: orderId, status: order.status },
      data: { status: "CANCELLED" },
    });
    if (result.count === 0) {
      throw new Error("Order sudah berubah, refresh dulu.");
    }
    didCancel = true;
  });

  const ctx = didCancel ? await getEmailContext(orderId) : null;
  if (ctx) {
    await sendOrderStatusEmail("CANCELLED", ctx).catch(() => {});
    await sendOrderStatusPush(orderId, ctx.orderNumber, "CANCELLED").catch(() => {});
    sendOrderCancelled(ctx).catch((error) => {
      console.error("[whatsapp] order cancelled notification failed", error);
    });
  }

  const allIdsToSync = [
    ...variantProductIdsToSync,
    ...nonVariantProductIdsToSync,
  ];
  if (allIdsToSync.length > 0) {
    try {
      const { syncProduct } = await import("@/lib/search");
      await Promise.all(allIdsToSync.map((pid) => syncProduct(pid)));
    } catch {
      // Search index sync gagal, tidak block cancel
    }
  }

  revalidateOrderAdmin(orderId);
}
