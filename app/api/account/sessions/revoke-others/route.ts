import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  MEMBER_SESSION_COOKIE,
  createSessionToken,
  getSession,
  getSessionCookieOptions,
} from "@/lib/auth";

/**
 * "Logout dari semua perangkat lain" — increment User.tokenVersion sehingga
 * semua JWT lama (di device lain) gagal `isTokenVersionCurrent` di getSession,
 * lalu issue JWT baru untuk device saat ini supaya user tetap login di sini.
 */
export async function POST(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Tidak ada sesi member aktif." }, { status: 401 });
  }

  let updated;
  try {
    updated = await prisma.user.update({
      where: { id: session.sub },
      data: { tokenVersion: { increment: 1 } },
      select: { id: true, name: true, tokenVersion: true },
    });
  } catch (error) {
    console.error("[sessions-revoke-others] failed:", error);
    return NextResponse.json(
      { error: "Gagal me-logout perangkat lain. Coba lagi." },
      { status: 500 }
    );
  }

  const token = await createSessionToken({
    sub: updated.id,
    role: "CUSTOMER",
    name: updated.name,
    tv: updated.tokenVersion,
  });

  const response = NextResponse.json({ ok: true });
  response.cookies.set(MEMBER_SESSION_COOKIE, token, getSessionCookieOptions(request));
  return response;
}
