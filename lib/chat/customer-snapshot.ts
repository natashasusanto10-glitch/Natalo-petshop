import { prisma } from "@/lib/prisma";
import { buildCustomerSnapshot, type CustomerSnapshot } from "@/lib/chat/rooms";

/** Nama akun bila diisi; kalau kosong pakai nama yang diketik saat checkout. */
export function pickCustomerName(
  accountName: string | null | undefined,
  checkoutName: string | null | undefined,
): string {
  return accountName?.trim() || checkoutName?.trim() || "";
}

/** Nomor HP akun bila diisi; kalau kosong pakai nomor saat checkout. */
export function pickCustomerPhone(
  accountPhone: string | null | undefined,
  checkoutPhone: string | null | undefined,
): string {
  return accountPhone?.trim() || checkoutPhone?.trim() || "";
}

// Sama dengan /api/chat/send: pesanan batal/refund/belum dibayar bukan
// riwayat belanja "nyata", jadi tidak ikut dihitung.
const NOT_COUNTED = ["CANCELLED", "REFUNDED", "PENDING"] as const;

/**
 * Snapshot pembeli untuk room chat yang dibuat tanpa pesan dari pembeli
 * (mis. kartu bukti transfer dari web). Pembeli web sering tak mengisi nama
 * akun -> nama/nomor diambil dari pesanan terakhirnya sebagai cadangan.
 */
export async function loadCustomerSnapshot(userId: string): Promise<CustomerSnapshot> {
  const [user, agg, lastPaid, lastAny] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { name: true, phone: true } }),
    prisma.order.aggregate({
      where: { userId, status: { notIn: [...NOT_COUNTED] } },
      _sum: { total: true },
      _count: true,
    }),
    prisma.order.findFirst({
      where: { userId, status: { notIn: [...NOT_COUNTED] } },
      orderBy: { createdAt: "desc" },
      select: { orderNumber: true, status: true, total: true },
    }),
    prisma.order.findFirst({
      where: { userId },
      orderBy: { createdAt: "desc" },
      select: { customerName: true, customerPhone: true },
    }),
  ]);
  return buildCustomerSnapshot(
    {
      name: pickCustomerName(user?.name, lastAny?.customerName),
      phone: pickCustomerPhone(user?.phone, lastAny?.customerPhone),
    },
    {
      totalBelanja: agg._sum.total ?? 0,
      orderCount: agg._count ?? 0,
      lastOrder: lastPaid
        ? { inv: lastPaid.orderNumber, status: lastPaid.status, total: lastPaid.total }
        : null,
    },
  );
}
