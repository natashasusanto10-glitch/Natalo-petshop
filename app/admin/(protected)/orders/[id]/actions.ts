"use server";

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { createBiteshipShipment } from "@/lib/biteship";
import { sendOrderStatusEmail } from "@/lib/email-order";
import { assertCanTransitionOrderStatus, transitionOrderStatus } from "@/lib/order-transitions";
import { sendOrderStatusPush } from "@/lib/push";
import {
  sendCancellationRejectedPush,
  sendRefundIssuedPush,
} from "@/lib/push-refund";
import { creditWallet } from "@/lib/refund-wallet";
import { SELF_PICKUP_METHOD, createPickupCode } from "@/lib/self-pickup";
import { AdminAction, logAdminAction } from "@/lib/admin-audit";
// Notifikasi order via WhatsApp dihapus — admin actions update status,
// customer dapat info via sendOrderStatusEmail + sendOrderStatusPush.
// Fonnte hanya dipakai untuk OTP (register & login).

/**
 * Guard semua admin server action. Layout (protected) hanya melindungi page render,
 * tapi server action bisa di-invoke langsung lewat POST. Tanpa check ini, customer
 * bisa eksekusi action admin (mark paid, cancel, dll) kalau tahu endpoint-nya.
 */
// Helper format Rp untuk audit log summary — concise tanpa import
// utility besar. `n` accepted as number atau null (defensive).
function formatRupiahLog(n: number | null | undefined): string {
  if (n === null || n === undefined) return "Rp—";
  return `Rp${new Intl.NumberFormat("id-ID").format(Math.round(n))}`;
}

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
  const session = await requireAdmin();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true, paymentStatus: true, orderType: true, orderNumber: true, total: true },
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
  }

  if (current.orderType !== SELF_PICKUP_METHOD) {
    await createBiteshipShipment(orderId).catch((error) => {
      console.error("[biteship] create shipment after manual payment failed", error);
    });
  }

  logAdminAction({
    actorUserId: session.sub,
    action: AdminAction.ORDER_MARK_PAID,
    targetType: "Order",
    targetId: orderId,
    summary: `Konfirmasi pembayaran order #${current.orderNumber} (${formatRupiahLog(current.total)})`,
    metadata: { total: current.total, orderType: current.orderType },
  });

  revalidateOrderAdmin(orderId);
}

export async function createShipment(orderId: string) {
  await requireAdmin();
  const result = await createBiteshipShipment(orderId);
  // Kalau Biteship disabled, kasih feedback admin via error supaya
  // tidak diam-diam (button "Booking Kurir" tidak ada effect = confusing).
  if ("reason" in result && result.reason === "biteship_disabled") {
    throw new Error(
      "Integrasi Biteship belum aktif. Booking kurir dilakukan manual: pakai aplikasi/website kurir (JNE/JNT/SiCepat/dll), lalu input nomor resi via tombol 'Tandai sudah dikirim'.",
    );
  }
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
  }
  revalidateOrderAdmin(orderId);
}

export async function markAsShipped(orderId: string, formData: FormData) {
  await requireAdmin();
  const courierType = String(formData.get("courierType") || "REGULAR")
    .trim()
    .toUpperCase();
  const trackingNumber = String(formData.get("trackingNumber") || "").trim();
  const shippingDriverInfo = String(formData.get("shippingDriverInfo") || "")
    .trim()
    .slice(0, 500); // cap length untuk keamanan + storage

  // ── Validation ──────────────────────────────────────────────────────
  // Cegah admin "tandai shipped" tanpa bukti pengiriman apapun.
  // - REGULAR (JNE, JNT, SiCepat, Pos, Anteraja, dll) → wajib resi
  // - INSTANT (Gojek, Grab, Lalamove, Borzo, dll) → wajib info driver
  //   karena kurir instant tidak punya resi tradisional
  if (courierType === "INSTANT") {
    if (shippingDriverInfo.length === 0) {
      throw new Error(
        "Info driver wajib diisi untuk kurir instant. Contoh: 'Nama: Pak Budi | HP: 0812xxxx | Plat: B 1234 ABC'.",
      );
    }
  } else {
    // REGULAR (default)
    if (trackingNumber.length === 0) {
      throw new Error(
        "Nomor resi wajib diisi untuk kurir regular (JNE/JNT/SiCepat/dst). Kalau pakai kurir instant (Gojek/Grab), pilih 'Kurir Instant' di form.",
      );
    }
  }

  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true },
  });
  if (!current) return;

  let didTransition = false;

  // Untuk REGULAR: simpan trackingNumber + clear driverInfo (defensive,
  // kalau admin sebelumnya isi keduanya lalu switch ke regular). Sebaliknya
  // untuk INSTANT: simpan driverInfo + clear resi.
  const shippingData =
    courierType === "INSTANT"
      ? {
          trackingNumber: null,
          shippingDriverInfo: shippingDriverInfo,
        }
      : {
          trackingNumber: trackingNumber,
          shippingDriverInfo: null,
        };

  if (current.status !== "SHIPPED") {
    await transitionOrderStatus(orderId, "SHIPPED", {
      ...shippingData,
      // Mark waktu shipped untuk cron auto-confirm-delivered.
      shippedAt: new Date(),
    });
    didTransition = true;
  } else {
    // Re-shipped (update tracking info aja) — JANGAN reset shippedAt
    // supaya counter 7 hari tetap dari tanggal shipped pertama.
    await prisma.order.updateMany({
      where: { id: orderId, status: "SHIPPED" },
      data: shippingData,
    });
  }

  if (didTransition) {
    const ctx = await getEmailContext(orderId);
    if (ctx) {
      await sendOrderStatusEmail("SHIPPED", ctx).catch(() => {});
      await sendOrderStatusPush(orderId, ctx.orderNumber, "SHIPPED").catch(() => {});
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
  const session = await requireAdmin();
  const variantProductIdsToSync = new Set<string>();
  const nonVariantProductIdsToSync = new Set<string>();
  let didCancel = false;
  let cancelledOrderNumber: string | null = null;
  let cancelledOrderTotal: number | null = null;
  let restoredStock = false;
  let reversedSaldo: number = 0;
  // Nominal yang otomatis di-refund ke Saldo Refund user pas cancel.
  // Selain reversedSaldo (saldo yang DIPAKAI bayar, dibalikin ke wallet),
  // ini cover sisa nominal yang user bayar via Midtrans/transfer/etc.
  // Sebelumnya: admin harus manual buka form refund + pilih reason
  // ORDER_CANCELLED + input nominal. Sekarang otomatis dalam transaction
  // yang sama supaya tidak ada celah "lupa refund setelah cancel" yang
  // berakibat duit user mengambang di kas Natalo.
  let autoRefundedAmount: number = 0;
  // Hoist RefundCase.id keluar transaction untuk push notif caseId yang
  // benar. Pakai order.id di sini bikin refund-detail link 404.
  let autoRefundCaseId: string | null = null;

  await prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({
      where: { id: orderId },
      include: { items: true },
    });
    if (!order || order.status === "CANCELLED") return;

    // Status guard ramah-pengguna sebelum hit assertCanTransitionOrderStatus
    // yang error message-nya generic ("Transisi status order tidak valid").
    // SHIPPED & DELIVERED memang sudah di-block oleh transition matrix di
    // lib/order-transitions.ts, ini cuma supaya admin dapat penjelasan yang
    // actionable.
    if (order.status === "SHIPPED") {
      throw new Error(
        `Order #${order.orderNumber} sudah dikirim. Paket sudah di kurir — tidak bisa dibatalkan. Kalau bermasalah, tunggu paket sampai lalu proses sebagai retur.`,
      );
    }
    if (order.status === "DELIVERED") {
      throw new Error(
        `Order #${order.orderNumber} sudah ditandai SELESAI. Pesanan yang sudah selesai tidak bisa dibatalkan.`,
      );
    }
    if (order.status === "REFUNDED") {
      throw new Error(
        `Order #${order.orderNumber} sudah ditandai REFUNDED — tidak perlu cancel ulang.`,
      );
    }

    assertCanTransitionOrderStatus(order.status, "CANCELLED");
    cancelledOrderNumber = order.orderNumber;
    cancelledOrderTotal = order.total;

    const shouldRestoreStock =
      order.status === "PENDING" ||
      order.status === "PAID" ||
      order.status === "PROCESSING";
    restoredStock = shouldRestoreStock;

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

    // Rollback voucher usage — mirror logic dari payment-failure rollback
    // di app/api/orders/route.ts. Sebelumnya admin-cancel TIDAK decrement
    // usedCount → voucher stuck di "consumed", dan user tidak bisa pakai
    // ulang (atau voucher kuota habis padahal order yg pakai sudah cancel).
    const voucherCodes = [...new Set([
      order.voucherCode,
      order.productVoucherCode,
      order.shippingVoucherCode,
      order.loyaltyVoucherCode,
      order.manualVoucherCode,
    ].filter((code): code is string => Boolean(code)))];
    if (voucherCodes.length > 0) {
      await tx.voucher.updateMany({
        where: { code: { in: voucherCodes }, usedCount: { gt: 0 } },
        data: { usedCount: { decrement: 1 } },
      });
    }

    // Hapus CustomerPoint yang di-grant dari order ini — customer harusnya
    // tidak keep points untuk order yang cancel.
    await tx.customerPoint.deleteMany({
      where: { source: `ORDER:${order.orderNumber}` },
    });

    // Reversal saldo refund — kalau order pakai saldo, balikin ke wallet.
    // Atomic dalam transaction yang sama dengan order update, supaya
    // cancel + reversal sukses/gagal bersama. Tanpa ini, saldo user
    // "hilang" saat order yang pakai saldo di-cancel admin.
    if (order.refundBalanceUsed > 0 && order.userId) {
      await creditWallet(
        {
          userId: order.userId,
          amount: order.refundBalanceUsed,
          sourceOrderId: orderId,
          note: `Pembatalan pesanan ${order.orderNumber}`,
          type: "REVERSAL",
        },
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        tx as any,
      );
      reversedSaldo = order.refundBalanceUsed;
    }

    // ── Auto-refund nominal yang user bayar (non-saldo) ──────────────
    // Sebelum patch ini, admin harus manual buka form refund + pilih
    // ORDER_CANCELLED + input nominal. Kalau lupa → duit user mengambang.
    //
    // Logika:
    //   - Hanya kalau paymentStatus === "PAID" (user beneran udah bayar)
    //   - Hanya kalau ada userId (guest checkout di-skip — tidak punya
    //     wallet, refund manual ke metode bayar asal)
    //   - Hitung sisa refundable = order.total − sum(existing CREDITED refund)
    //     supaya kalau admin sudah refund sebagian sebelumnya (mis. OOS
    //     per-item), cancel hanya nge-refund sisanya (no double-credit)
    //   - Skip kalau sisa ≤ 0 (sudah full refunded sebelum di-cancel)
    if (order.paymentStatus === "PAID" && order.userId) {
      const existing = await tx.refundCase.aggregate({
        where: { orderId, status: "CREDITED" },
        _sum: { amount: true },
      });
      const alreadyRefunded = existing._sum.amount ?? 0;
      const amountToRefund = order.total - alreadyRefunded;

      if (amountToRefund > 0) {
        const refundCase = await tx.refundCase.create({
          data: {
            orderId,
            userId: order.userId,
            reason: "ORDER_CANCELLED",
            amount: amountToRefund,
            destination: "REFUND_BALANCE",
            status: "PENDING",
            adminNote: `Auto-refund pembatalan order ${order.orderNumber}`,
            createdByAdminId: session.sub,
          },
        });

        const credit = await creditWallet(
          {
            userId: order.userId,
            amount: amountToRefund,
            sourceOrderId: orderId,
            sourceRefundCaseId: refundCase.id,
            note: `Auto-refund pembatalan order ${order.orderNumber}`,
            createdByAdminId: session.sub,
            type: "CREDIT",
          },
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          tx as any,
        );

        await tx.refundCase.update({
          where: { id: refundCase.id },
          data: {
            status: "CREDITED",
            approvedAt: new Date(),
            creditedAt: new Date(),
            ledgerEntryId: credit.ledgerEntryId,
          },
        });

        autoRefundedAmount = amountToRefund;
        autoRefundCaseId = refundCase.id;
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

  // Push notif user — auto-refund jadi instant feedback ke customer.
  // WAJIB await — void promise bisa dibekukan Vercel sebelum jalan →
  // notif refund hilang; kalau push service down, cancel tetap tercatat
  // (helper menelan error). Kirim hanya kalau ada auto-refund (kalau cuma
  // cancel PENDING tanpa bayar, user gak perlu notif refund — sudah dapat
  // notif cancel via sendOrderStatusPush di atas).
  if (
    didCancel &&
    autoRefundedAmount > 0 &&
    cancelledOrderNumber &&
    autoRefundCaseId != null
  ) {
    const orderInfo = await prisma.order.findUnique({
      where: { id: orderId },
      select: { userId: true },
    });
    if (orderInfo?.userId) {
      await sendRefundIssuedPush({
        userId: orderInfo.userId,
        // RefundCase.id, BUKAN orderId — deep link /member/refund-detail
        // resolve via GET /api/member/refund-cases/{id} yang cari by
        // RefundCase.id. order.id → 404 NOT_FOUND.
        caseId: autoRefundCaseId,
        amount: autoRefundedAmount,
        reason: "ORDER_CANCELLED",
        itemName: null,
        adminNote: `Pembatalan order ${cancelledOrderNumber}`,
      });
    }
  }

  if (didCancel && cancelledOrderNumber) {
    const summaryParts: string[] = [
      `Cancel order #${cancelledOrderNumber} (${formatRupiahLog(cancelledOrderTotal)})`,
    ];
    if (autoRefundedAmount > 0) {
      summaryParts.push(`+auto-refund ${formatRupiahLog(autoRefundedAmount)} ke Saldo`);
    }
    if (reversedSaldo > 0) {
      summaryParts.push(`reversal saldo ${formatRupiahLog(reversedSaldo)}`);
    }
    logAdminAction({
      actorUserId: session.sub,
      action: AdminAction.ORDER_CANCELLED,
      targetType: "Order",
      targetId: orderId,
      summary: summaryParts.join(" · "),
      metadata: {
        orderNumber: cancelledOrderNumber,
        total: cancelledOrderTotal,
        restoredStock,
        reversedSaldo,
        autoRefundedAmount,
      },
    });
  }

  revalidateOrderAdmin(orderId);
}

/**
 * Result type untuk `issueRefundToWallet` server action.
 * Dipakai dengan `useActionState` di RefundFormClient supaya admin
 * dapat success/error banner tanpa reload page atau error boundary.
 *
 * ok=true → tampil banner hijau dengan amount + timestamp.
 * ok=false → tampil banner merah dengan message.
 * Initial state (sebelum first submit): { ok: false, message: '' }.
 */
export type RefundActionResult = {
  ok: boolean;
  message: string;
  amount?: number;
  /** ISO timestamp untuk client-side date format. */
  timestamp?: string;
};

/**
 * Issue refund ke Saldo Refund user.
 *
 * Admin action — create RefundCase + credit RefundWallet atomically.
 * Untuk MVP, admin input refund amount manual (auto-calc voucher
 * allocation deferred — order schema belum track per-voucher breakdown).
 *
 * FormData:
 *  - amount: number (Rupiah, > 0)
 *  - reason: RefundCaseReason enum
 *  - itemId: string | "" (kosong = whole order refund)
 *  - adminNote: string (opsional, display ke user)
 *
 * Signature compatible dengan `useActionState`:
 *   (orderId, prevState, formData) => Promise<RefundActionResult>
 * Setelah `.bind(null, orderId)`:
 *   (prevState, formData) => Promise<RefundActionResult>
 *
 * Validation/business errors di-return sebagai { ok: false, message }
 * supaya client bisa display di banner. Auth/system errors tetap throw
 * (akan triggered error boundary — itu kasus exceptional).
 */
export async function issueRefundToWallet(
  orderId: string,
  _prevState: RefundActionResult,
  formData: FormData,
): Promise<RefundActionResult> {
  const session = await requireAdmin();
  const adminId = session.sub;

  const amountRaw = formData.get("amount");
  const reasonRaw = formData.get("reason");
  const itemIdRaw = formData.get("itemId");
  const adminNoteRaw = formData.get("adminNote");

  const amount = parseInt(String(amountRaw ?? "0"), 10);
  if (!Number.isFinite(amount) || amount <= 0) {
    return { ok: false, message: "Nominal refund harus lebih dari Rp0." };
  }
  if (amount > 100_000_000) {
    return {
      ok: false,
      message: "Nominal refund > Rp100jt — butuh approval level lebih tinggi.",
    };
  }

  const VALID_REASONS = [
    "OUT_OF_STOCK",
    "PARTIAL_CANCEL",
    "RETURN_APPROVED",
    "ORDER_CANCELLED",
    "OTHER",
  ] as const;
  const reason = String(reasonRaw ?? "") as (typeof VALID_REASONS)[number];
  if (!VALID_REASONS.includes(reason)) {
    return { ok: false, message: `Reason tidak valid: ${reason}` };
  }

  const itemId = itemIdRaw ? String(itemIdRaw) : null;
  const adminNote = adminNoteRaw ? String(adminNoteRaw).trim().slice(0, 500) : null;

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      id: true,
      userId: true,
      total: true,
      status: true,
      paymentStatus: true,
      orderNumber: true,
    },
  });
  if (!order) return { ok: false, message: "Order tidak ditemukan." };
  if (!order.userId) {
    return {
      ok: false,
      message:
        "Order ini guest checkout — tidak bisa refund ke Saldo Refund. Pakai refund manual ke metode bayar asal.",
    };
  }

  // ── Status guard: cegah refund pada order yang sudah final ──────────
  // Spec dari owner: kalau order udah DELIVERED (sampai di customer dan
  // ditandai selesai), refund tidak boleh dilakukan lagi — komplain harus
  // sebelum mark selesai. CANCELLED & REFUNDED juga terminal: tidak ada
  // saldo / barang yang bisa di-refund tambah lagi.
  //
  // Ini patch pertama dari rencana refactor "user-driven completion"
  // (Shopee/Tokopedia pattern). Fase berikutnya: pindahkan trigger
  // markAsDelivered dari admin ke user + auto-confirm cron 3 hari.
  if (order.status === "DELIVERED") {
    return {
      ok: false,
      message: `Order #${order.orderNumber} sudah ditandai SELESAI. Refund hanya bisa sebelum pesanan ditandai selesai oleh customer.`,
    };
  }
  if (order.status === "CANCELLED") {
    return {
      ok: false,
      message: `Order #${order.orderNumber} sudah dibatalkan — refund saldo tidak bisa dilakukan di order CANCELLED. Cancel sudah otomatis me-reverse saldo yang dipakai.`,
    };
  }
  if (order.status === "REFUNDED") {
    return {
      ok: false,
      message: `Order #${order.orderNumber} sudah ditandai REFUNDED (full refund). Tidak bisa refund tambahan.`,
    };
  }
  // Payment guard — sama dengan markItemPartiallyOutOfStock + cancel flow.
  // Refund ke SALDO hanya untuk order yang uangnya sudah masuk (PAID).
  // PENDING (manual transfer "Menunggu verifikasi") = state default, uang
  // belum tentu diterima → kredit wallet di sini = kebocoran.
  if (order.paymentStatus !== "PAID") {
    return {
      ok: false,
      message: `Order #${order.orderNumber} belum lunas. Refund ke Saldo hanya untuk order yang sudah dibayar. Verifikasi pembayaran dulu, atau batalkan order kalau dana belum masuk.`,
    };
  }

  const refundUserId = order.userId;

  // ── Validasi max refund amount per item / per order ────────────────
  // Cegah admin over-refund (typo nominal, atau bug client side). Logic:
  //   - Partial refund (itemId): max = item.lineTotal − sum(existing CREDITED
  //     refund for same item). Multiple partial refund allowed selama
  //     cumulative <= line total.
  //   - Whole order refund (no itemId): max = order.total − sum(existing
  //     CREDITED refund for whole order). Item-specific refund SEPARATE
  //     dari order-level refund — ini guard order-level only.
  //
  // Anti-abuse: kalau admin punya akses dashboard tapi malicious / typo
  // ngetik Rp50jt buat item Rp5rb, validation block sebelum credit wallet.
  let maxAllowedRefund: number;
  let validationContext: string;
  if (itemId) {
    const item = await prisma.orderItem.findUnique({
      where: { id: itemId },
      select: { orderId: true, price: true, quantity: true, name: true },
    });
    if (!item || item.orderId !== orderId) {
      return { ok: false, message: "Item tidak ditemukan di order ini." };
    }
    const itemLineTotal = item.price * item.quantity;
    const existingItemRefund = await prisma.refundCase.aggregate({
      where: {
        orderId,
        orderItemId: itemId,
        status: "CREDITED",
      },
      _sum: { amount: true },
    });
    const alreadyRefunded = existingItemRefund._sum.amount ?? 0;
    maxAllowedRefund = itemLineTotal - alreadyRefunded;
    validationContext = `item "${item.name}" (line total ${itemLineTotal}, sudah ke-refund ${alreadyRefunded})`;
  } else {
    const existingOrderRefund = await prisma.refundCase.aggregate({
      where: {
        orderId,
        orderItemId: null, // whole-order refund only
        status: "CREDITED",
      },
      _sum: { amount: true },
    });
    const alreadyRefunded = existingOrderRefund._sum.amount ?? 0;
    maxAllowedRefund = order.total - alreadyRefunded;
    validationContext = `order ini (total ${order.total}, sudah ke-refund ${alreadyRefunded})`;
  }
  if (amount > maxAllowedRefund) {
    if (maxAllowedRefund <= 0) {
      return {
        ok: false,
        message: `Refund untuk ${validationContext} sudah penuh. Tidak bisa refund tambahan.`,
      };
    }
    return {
      ok: false,
      message: `Nominal refund (Rp${amount.toLocaleString("id-ID")}) melebihi maksimum (Rp${maxAllowedRefund.toLocaleString("id-ID")}) untuk ${validationContext}.`,
    };
  }

  // Create RefundCase as PENDING dulu. Kalau credit sukses → CREDITED.
  // Kalau credit fail → REJECTED dengan error message di adminNote.
  const refundCase = await prisma.refundCase.create({
    data: {
      orderId,
      orderItemId: itemId,
      userId: refundUserId,
      reason,
      amount,
      destination: "REFUND_BALANCE",
      status: "PENDING",
      adminNote,
      createdByAdminId: adminId,
    },
  });

  try {
    const credit = await creditWallet({
      userId: refundUserId,
      amount,
      sourceOrderId: orderId,
      sourceRefundCaseId: refundCase.id,
      note: adminNote ?? `Refund ${reason.toLowerCase().replace(/_/g, " ")}`,
      createdByAdminId: adminId,
      type: "CREDIT",
    });

    await prisma.refundCase.update({
      where: { id: refundCase.id },
      data: {
        status: "CREDITED",
        approvedAt: new Date(),
        creditedAt: new Date(),
        ledgerEntryId: credit.ledgerEntryId,
      },
    });

    // Push notification ke user — WAJIB await, void promise bisa dibekukan
    // Vercel sebelum jalan → notif refund hilang. Helper menelan error
    // sendiri, jadi push service down tidak mem-block admin action. Fetch
    // item name kalau partial refund (untuk display di notif body).
    let itemName: string | null = null;
    if (itemId) {
      const item = await prisma.orderItem
        .findUnique({
          where: { id: itemId },
          select: { name: true },
        })
        .catch(() => null);
      itemName = item?.name ?? null;
    }
    await sendRefundIssuedPush({
      userId: refundUserId,
      caseId: refundCase.id,
      amount,
      reason,
      itemName,
      adminNote,
    });

    logAdminAction({
      actorUserId: adminId,
      action: AdminAction.REFUND_ISSUED,
      targetType: "RefundCase",
      targetId: refundCase.id,
      summary: `Issue refund ${formatRupiahLog(amount)} ke order ${orderId.slice(0, 8)} (${reason}${itemId ? ` · item: ${itemName ?? itemId}` : " · seluruh order"})`,
      metadata: {
        orderId,
        itemId: itemId ?? null,
        amount,
        reason,
        adminNote,
      },
    });
  } catch (err) {
    const errMessage = err instanceof Error ? err.message : String(err);
    await prisma.refundCase.update({
      where: { id: refundCase.id },
      data: {
        status: "REJECTED",
        adminNote: `${adminNote ?? ""}\n[SYSTEM] Credit failed: ${errMessage}`.trim(),
      },
    });
    return {
      ok: false,
      message: `Gagal kredit saldo: ${errMessage}`,
    };
  }

  revalidateOrderAdmin(orderId);
  return {
    ok: true,
    message: `Refund Rp${amount.toLocaleString("id-ID")} berhasil dikredit ke Saldo Refund user.`,
    amount,
    timestamp: new Date().toISOString(),
  };
}

/**
 * Quick action: tandai item kosong saat packing → auto-refund.
 *
 * Pattern UX: admin tap tombol di item card → input qty pcs yang
 * missing → submit. Sistem otomatis:
 *   1. Hitung refund amount = missingQty × itemPrice × (1 − voucher_ratio)
 *      (net-of-voucher proportional, sama logic dengan RefundFormClient)
 *   2. Create RefundCase reason=OUT_OF_STOCK
 *   3. Credit wallet user
 *   4. Auto-fill admin note "Item kosong saat packing"
 *   5. Fire push notif
 *
 * Bedanya dengan issueRefundToWallet manual: admin TIDAK perlu hitung
 * sendiri atau pilih dari dropdown — tinggal klik per-item + qty.
 * Internally panggil flow yang sama (reuse credit logic), cuma form
 * inputs auto-derived.
 *
 * Validation: max missingQty = item.quantity. Block kalau item udah
 * pernah di-refund full (via max-refund guard di issueRefundToWallet).
 */
export async function markItemPartiallyOutOfStock(
  orderId: string,
  formData: FormData,
): Promise<void> {
  const session = await requireAdmin();
  const adminId = session.sub;

  const itemId = String(formData.get("itemId") ?? "");
  const missingQtyRaw = formData.get("missingQty");
  const missingQty = parseInt(String(missingQtyRaw ?? "0"), 10);
  const customNote = String(formData.get("adminNote") ?? "").trim();

  if (!itemId) throw new Error("Item ID kosong.");
  if (!Number.isFinite(missingQty) || missingQty <= 0) {
    throw new Error("Jumlah pcs yang kosong harus lebih dari 0.");
  }

  // Fetch item + order untuk validasi + voucher allocation.
  const item = await prisma.orderItem.findUnique({
    where: { id: itemId },
    select: {
      orderId: true,
      name: true,
      price: true,
      quantity: true,
    },
  });
  if (!item || item.orderId !== orderId) {
    throw new Error("Item tidak ditemukan di order ini.");
  }
  if (missingQty > item.quantity) {
    throw new Error(
      `Qty kosong (${missingQty}) melebihi qty di order (${item.quantity}).`,
    );
  }

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      id: true,
      userId: true,
      subtotal: true,
      productDiscount: true,
      status: true,
      paymentStatus: true,
      orderNumber: true,
    },
  });
  if (!order) throw new Error("Order tidak ditemukan.");
  if (!order.userId) {
    throw new Error(
      "Order guest checkout — tidak bisa refund ke Saldo. Refund manual ke metode bayar asal.",
    );
  }

  // Guard pembayaran — refund ke SALDO hanya boleh kalau uang sudah benar
  // masuk (paymentStatus PAID). Untuk order manual, PENDING = "Menunggu
  // verifikasi" adalah state DEFAULT begitu order dibuat — uang belum tentu
  // masuk. Kalau kita kredit wallet di sini, Natalo kasih saldo nyata yang
  // bisa dibelanjakan untuk uang yang BELUM diterima → kebocoran.
  //
  // Konsisten dengan cancel flow (markAsCancelled line ~468) yang juga guard
  // paymentStatus === "PAID" sebelum auto-refund. Admin yang ketemu item
  // kosong di order belum-lunas: verifikasi pembayaran dulu (tandai Lunas)
  // lalu refund, ATAU batalkan order (cancel restore stok + notif user,
  // tanpa kredit saldo karena memang belum bayar).
  if (order.paymentStatus !== "PAID") {
    throw new Error(
      `Order #${order.orderNumber} belum lunas (status bayar belum PAID). ` +
        `Refund item kosong ke Saldo hanya untuk order yang sudah dibayar. ` +
        `Verifikasi pembayaran dulu lalu refund, atau batalkan order kalau dana belum masuk.`,
    );
  }

  // Status guard sama dengan issueRefundToWallet — refund (termasuk OOS
  // quick action) tidak boleh dilakukan setelah order DELIVERED / CANCELLED
  // / REFUNDED. Lihat catatan panjang di issueRefundToWallet.
  if (order.status === "DELIVERED") {
    throw new Error(
      `Order #${order.orderNumber} sudah SELESAI. Refund item kosong harus dilakukan sebelum pesanan ditandai selesai oleh customer.`,
    );
  }
  if (order.status === "CANCELLED") {
    throw new Error(
      `Order #${order.orderNumber} sudah dibatalkan — refund item tidak bisa dilakukan. Cancel sudah otomatis me-reverse saldo yang dipakai.`,
    );
  }
  if (order.status === "REFUNDED") {
    throw new Error(
      `Order #${order.orderNumber} sudah ditandai REFUNDED. Tidak bisa refund tambahan.`,
    );
  }

  const refundUserId = order.userId;

  // Auto-calc net-of-voucher amount — sama formula dengan RefundFormClient.
  const discountRatio =
    order.subtotal > 0 ? Math.min(1, order.productDiscount / order.subtotal) : 0;
  const grossAmount = item.price * missingQty;
  const netAmount = Math.round(grossAmount * (1 - discountRatio));
  // Default mode: net (recommended). Kalau order tanpa voucher,
  // netAmount === grossAmount jadi sama aja.
  const amount = netAmount;

  if (amount <= 0) {
    throw new Error("Nominal refund 0 setelah voucher allocation — cek manual via form refund.");
  }

  // Cek max allowed refund (cumulative existing) — defensive walau
  // qty udah di-bound oleh item.quantity. Bisa overflow kalau ada
  // refund sebelumnya.
  const existingItemRefund = await prisma.refundCase.aggregate({
    where: {
      orderId,
      orderItemId: itemId,
      status: "CREDITED",
    },
    _sum: { amount: true },
  });
  const alreadyRefunded = existingItemRefund._sum.amount ?? 0;
  const itemMaxRefund = item.price * item.quantity * (1 - discountRatio);
  const maxAllowedRefund = Math.round(itemMaxRefund - alreadyRefunded);
  if (amount > maxAllowedRefund) {
    throw new Error(
      `Refund (Rp${amount.toLocaleString("id-ID")}) melebihi sisa (Rp${maxAllowedRefund.toLocaleString("id-ID")}) untuk item ini. Sudah ke-refund Rp${alreadyRefunded.toLocaleString("id-ID")}.`,
    );
  }

  const adminNote = customNote.length > 0
    ? customNote.slice(0, 500)
    : `${missingQty} pcs "${item.name}" kosong saat packing.`;

  const refundCase = await prisma.refundCase.create({
    data: {
      orderId,
      orderItemId: itemId,
      userId: refundUserId,
      reason: "OUT_OF_STOCK",
      amount,
      destination: "REFUND_BALANCE",
      status: "PENDING",
      adminNote,
      createdByAdminId: adminId,
    },
  });

  try {
    const credit = await creditWallet({
      userId: refundUserId,
      amount,
      sourceOrderId: orderId,
      sourceRefundCaseId: refundCase.id,
      note: adminNote,
      createdByAdminId: adminId,
      type: "CREDIT",
    });
    await prisma.refundCase.update({
      where: { id: refundCase.id },
      data: {
        status: "CREDITED",
        approvedAt: new Date(),
        creditedAt: new Date(),
        ledgerEntryId: credit.ledgerEntryId,
      },
    });

    // WAJIB await — alasan sama dengan refund push di atas.
    await sendRefundIssuedPush({
      userId: refundUserId,
      caseId: refundCase.id,
      amount,
      reason: "OUT_OF_STOCK",
      itemName: item.name,
      adminNote,
    });

    logAdminAction({
      actorUserId: adminId,
      action: AdminAction.REFUND_ITEM_OOS,
      targetType: "RefundCase",
      targetId: refundCase.id,
      summary: `Item kosong: ${missingQty} pcs "${item.name}" → refund ${formatRupiahLog(amount)}`,
      metadata: {
        orderId,
        itemId,
        itemName: item.name,
        missingQty,
        amount,
        discountRatio,
      },
    });
  } catch (err) {
    await prisma.refundCase.update({
      where: { id: refundCase.id },
      data: {
        status: "REJECTED",
        adminNote: `${adminNote}\n[SYSTEM] Credit failed: ${
          err instanceof Error ? err.message : String(err)
        }`,
      },
    });
    throw err;
  }

  revalidateOrderAdmin(orderId);
}

// ─────────────────────────────────────────────────────────────────────────
// Cancellation request approval (Shopee/Tokopedia pattern)
// ─────────────────────────────────────────────────────────────────────────
//
// Saat order udah PAID dan user pencet "Batalkan" di app, order TIDAK
// langsung di-cancel — request masuk antrian (lihat
// app/api/orders/[orderNumber]/cancel/route.ts). Dua action di bawah ini
// yang admin pakai untuk merespons:
//   - approveCancellationRequest: jalankan flow markAsCancelled standar
//     (auto-refund + restore stock + voucher rollback) + tandai request
//     APPROVED.
//   - rejectCancellationRequest: tandai REJECTED + simpan reject reason
//     + notif ke user. Status order tidak berubah.

export async function approveCancellationRequest(orderId: string) {
  const session = await requireAdmin();
  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      orderNumber: true,
      cancellationRequestStatus: true,
      cancellationReason: true,
    },
  });
  if (!current) throw new Error("Order tidak ditemukan.");
  if (current.cancellationRequestStatus !== "PENDING") {
    throw new Error(
      "Tidak ada permintaan pembatalan PENDING untuk order ini.",
    );
  }

  // Mark request as APPROVED first (so subsequent UI render shows the
  // response timestamp + admin id correctly), then run cancel flow.
  await prisma.order.update({
    where: { id: orderId },
    data: {
      cancellationRequestStatus: "APPROVED",
      cancellationRespondedAt: new Date(),
      cancellationRespondedByAdminId: session.sub,
    },
  });

  // markAsCancelled handles: stock restore, voucher rollback, points
  // delete, saldo reversal, auto-refund (kalau paymentStatus=PAID, which
  // is the precondition untuk request mode), status → CANCELLED,
  // push notif, audit log. Reuse penuh — DRY.
  await markAsCancelled(orderId);

  logAdminAction({
    actorUserId: session.sub,
    action: AdminAction.ORDER_CANCEL_REQUEST_APPROVED,
    targetType: "Order",
    targetId: orderId,
    summary: `Approve cancel request order #${current.orderNumber}${
      current.cancellationReason ? ` (${current.cancellationReason})` : ""
    }`,
    metadata: {
      orderNumber: current.orderNumber,
      userReason: current.cancellationReason,
    },
  });

  // revalidate sudah dilakukan markAsCancelled, tapi panggil lagi defensive
  // setelah audit log (no-op kalau path udah re-validated dalam request).
  revalidateOrderAdmin(orderId);
}

export async function rejectCancellationRequest(
  orderId: string,
  formData: FormData,
): Promise<void> {
  const session = await requireAdmin();
  const rejectReason = String(formData.get("rejectReason") ?? "")
    .trim()
    .slice(0, 500);
  if (rejectReason.length === 0) {
    throw new Error("Alasan penolakan wajib diisi.");
  }

  const current = await prisma.order.findUnique({
    where: { id: orderId },
    select: {
      orderNumber: true,
      userId: true,
      cancellationRequestStatus: true,
      cancellationReason: true,
    },
  });
  if (!current) throw new Error("Order tidak ditemukan.");
  if (current.cancellationRequestStatus !== "PENDING") {
    throw new Error(
      "Tidak ada permintaan pembatalan PENDING untuk order ini.",
    );
  }

  await prisma.order.update({
    where: { id: orderId },
    data: {
      cancellationRequestStatus: "REJECTED",
      cancellationRespondedAt: new Date(),
      cancellationRespondedByAdminId: session.sub,
      cancellationRejectReason: rejectReason,
    },
  });

  // Push notif ke user — informasi reject + alasan. WAJIB await — void
  // promise bisa dibekukan Vercel sebelum jalan → notif hilang; kalau
  // gagal admin action tetap commit (helper menelan error). User juga
  // akan lihat banner reject di order detail saat refresh
  // (defense-in-depth).
  if (current.userId) {
    await sendCancellationRejectedPush({
      userId: current.userId,
      orderId,
      orderNumber: current.orderNumber,
      rejectReason,
    });
  } else {
    console.log(
      `[cancel-reject] guest order=${current.orderNumber} (no userId, skip push)`,
    );
  }

  logAdminAction({
    actorUserId: session.sub,
    action: AdminAction.ORDER_CANCEL_REQUEST_REJECTED,
    targetType: "Order",
    targetId: orderId,
    summary: `Tolak cancel request order #${current.orderNumber} — "${rejectReason.slice(0, 80)}${rejectReason.length > 80 ? "…" : ""}"`,
    metadata: {
      orderNumber: current.orderNumber,
      userReason: current.cancellationReason,
      rejectReason,
    },
  });

  revalidateOrderAdmin(orderId);
}
