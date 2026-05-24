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
 *     sourceOrderId, sourceRefundCaseId, note, createdAt
 *   }]
 * }
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
      sourceRefundCaseId: entry.sourceRefundCaseId,
      note: entry.note,
      createdAt: entry.createdAt.toISOString(),
    })),
  });
}
