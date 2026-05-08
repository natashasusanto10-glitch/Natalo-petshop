import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  ADMIN_SESSION_COOKIE,
  LEGACY_SESSION_COOKIE,
  MEMBER_SESSION_COOKIE,
  getSession,
} from "@/lib/auth";

const CONFIRMATION_PHRASE = "HAPUS AKUN SAYA";

export async function POST(request: Request) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Tidak ada sesi member aktif." }, { status: 401 });
  }

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Body tidak valid." }, { status: 400 });
  }

  const confirmation = String(body.confirmation || "").trim();
  if (confirmation !== CONFIRMATION_PHRASE) {
    return NextResponse.json(
      { error: `Konfirmasi harus berupa "${CONFIRMATION_PHRASE}".` },
      { status: 400 }
    );
  }

  const reason = String(body.reason || "tidak_dijelaskan").slice(0, 50);

  try {
    await prisma.$transaction(async (tx) => {
      const userId = session.sub;

      // Preserve order history for accounting — orders.userId is nullable.
      await tx.order.updateMany({ where: { userId }, data: { userId: null } });

      // Push subscriptions: nullable userId, just detach.
      await tx.pushSubscription.updateMany({ where: { userId }, data: { userId: null } });

      // Relations without onDelete: Cascade — explicitly clean.
      await tx.reviewVote.deleteMany({ where: { userId } });
      await tx.review.deleteMany({ where: { userId } });
      await tx.customerPoint.deleteMany({ where: { userId } });
      await tx.voucher.deleteMany({ where: { userId } });
      await tx.passwordResetToken.deleteMany({ where: { userId } });

      // The user delete cascades to: addresses, favorites, pets, cartItems, chatThreads,
      // chatMessages (via thread), reviewReplies of reviews already removed above.
      await tx.user.delete({ where: { id: userId } });
    });
  } catch (error) {
    console.error("[account-delete] failed:", { reason, error });
    return NextResponse.json(
      { error: "Gagal menghapus akun. Silakan hubungi admin." },
      { status: 500 }
    );
  }

  const response = NextResponse.json({ ok: true });
  for (const name of [MEMBER_SESSION_COOKIE, ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE]) {
    response.cookies.set(name, "", { httpOnly: true, path: "/", maxAge: 0 });
  }
  return response;
}
