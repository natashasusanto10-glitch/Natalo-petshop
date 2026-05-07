"use server";

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { sendOrderStatusEmail } from "@/lib/email-order";
import { assertCanTransitionOrderStatus, transitionOrderStatus } from "@/lib/order-transitions";
import {
  sendOrderCancelled,
  sendOrderCompleted,
  sendOrderShipped,
  sendPaymentConfirmed,
} from "@/lib/whatsapp";

function revalidateOrderAdmin(orderId: string) {
  revalidatePath(`/admin/orders/${orderId}`);
  revalidatePath("/admin/orders");
  revalidatePath("/admin");
  revalidatePath("/admin/dashboard");
}

export async function getEmailContext(orderId: string) {
  return prisma.order.findUnique({
    where: { id: orderId },
    select: {
      orderNumber: true,
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
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true, paymentStatus: true },
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
    data: current.status === "PENDING"
      ? { paymentStatus: "PAID", status: "PAID" }
      : { paymentStatus: "PAID" },
  });
  if (result.count === 0) {
    throw new Error("Order sudah berubah, refresh halaman dulu.");
  }

  const ctx = await getEmailContext(orderId);
  if (ctx) {
    await sendOrderStatusEmail("PAID", ctx).catch(() => {});
    sendPaymentConfirmed(ctx).catch((error) => {
      console.error("[whatsapp] payment confirmed notification failed", error);
    });
  }
  revalidateOrderAdmin(orderId);
}

export async function markAsProcessing(orderId: string) {
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true, paymentStatus: true },
  });
  if (!current) return;
  if (current.paymentStatus !== "PAID") {
    throw new Error("Order belum lunas, belum bisa mulai packing.");
  }

  await transitionOrderStatus(orderId, "PROCESSING");
  revalidateOrderAdmin(orderId);
}

export async function markAsShipped(orderId: string, formData: FormData) {
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
      sendOrderShipped(ctx).catch((error) => {
        console.error("[whatsapp] order shipped notification failed", error);
      });
    }
  }

  revalidateOrderAdmin(orderId);
}

export async function markAsDelivered(orderId: string) {
  await transitionOrderStatus(orderId, "DELIVERED");
  const ctx = await getEmailContext(orderId);
  if (ctx) {
    await sendOrderStatusEmail("DELIVERED", ctx).catch(() => {});
    sendOrderCompleted(ctx).catch((error) => {
      console.error("[whatsapp] order completed notification failed", error);
    });
  }
  revalidateOrderAdmin(orderId);
}

export async function markAsCancelled(orderId: string) {
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
