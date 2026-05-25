/**
 * GET /api/member/refund-balance
 *
 * Return saldo refund user + history ledger (latest 50 entries).
 * Lazy-init wallet kalau belum ada (return availableBalance: 0).
 *
 * Response:
 * {
 *   wallet: { availableBalance, pendingBalance, status, currency: "IDR" },
 *   history: [{
 *     id, type, amount, balanceBefore, balanceAfter,
 *     sourceOrderId, sourceOrderNumber, sourceRefundCaseId, note, createdAt
 *   }]
 * }
 *
 * sourceOrderNumber: human-readable order number (ORD-...) — di-resolve
 * server-side dari sourceOrderId supaya Flutter bisa langsung navigate
 * ke detail order tanpa extra round-trip. Null kalau order udah dihapus.
 *
 * Guest dapat 401 — saldo refund wajib login.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { getOrCreateWallet } from "@/lib/refund-wallet";

const HISTORY_PAGE_SIZE = 50;

export async function GET(_request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "LOGIN_REQUIRED", message: "Login dulu untuk lihat saldo." },
      { status: 401 },
    );
  }

  // Lazy-create wallet kalau user pertama kali akses. Wallet baru
  // available balance = 0, status = ACTIVE.
  const wallet = await getOrCreateWallet(session.sub);

  const history = await prisma.refundWalletLedger.findMany({
    where: { walletId: wallet.id },
    orderBy: { createdAt: "desc" },
    take: HISTORY_PAGE_SIZE,
  });

  // Resolve orderNumber untuk semua entry yang punya sourceOrderId.
  // Single batch query — 1 round-trip, bukan N. Order yang udah dihapus
  // (cascade dari user / dev reset) gak muncul di map → sourceOrderNumber
  // null, Flutter fallback ke disable tap.
  const orderIds = Array.from(
    new Set(
      history
        .map((e) => e.sourceOrderId)
        .filter((id): id is string => typeof id === "string" && id.length > 0),
    ),
  );
  const orderMap = new Map<string, string>();
  if (orderIds.length > 0) {
    const orders = await prisma.order.findMany({
      where: { id: { in: orderIds } },
      select: { id: true, orderNumber: true },
    });
    for (const o of orders) {
      orderMap.set(o.id, o.orderNumber);
    }
  }

  return NextResponse.json({
    wallet: {
      availableBalance: wallet.availableBalance,
      pendingBalance: wallet.pendingBalance,
      status: wallet.status,
      currency: "IDR",
    },
    history: history.map((entry) => ({
      id: entry.id,
      type: entry.type,
      amount: entry.amount,
      balanceBefore: entry.balanceBefore,
      balanceAfter: entry.balanceAfter,
      sourceOrderId: entry.sourceOrderId,
      sourceOrderNumber: entry.sourceOrderId
        ? orderMap.get(entry.sourceOrderId) ?? null
        : null,
      sourceRefundCaseId: entry.sourceRefundCaseId,
      note: entry.note,
      createdAt: entry.createdAt.toISOString(),
    })),
  });
}
