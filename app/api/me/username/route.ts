/**
 * GET /api/me/username — return current user's username state.
 * PATCH /api/me/username — set or change username.
 *
 * Validation:
 *   - Format check via validateUsernameFormat (lib/username.ts)
 *   - Availability check (current owners + 30-day reservation)
 *
 * Lihat lib/username.ts untuk full rules.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  validateUsernameFormat,
  setUserUsername,
  normalizeUsername,
  UsernameCooldownError,
  USERNAME_CHANGE_COOLDOWN_DAYS,
} from "@/lib/username";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk akses username." },
      { status: 401 },
    );
  }

  const user = await prisma.user.findUnique({
    where: { id: session.sub },
    select: { username: true, usernameUpdatedAt: true },
  });
  if (!user) {
    return NextResponse.json({ error: "User tidak ditemukan." }, { status: 404 });
  }

  // Ganti pertama kali (dari auto-assign registrasi) selalu gratis —
  // cooldown baru berlaku mulai ganti kedua. Lihat setUserUsername.
  const priorChangeCount = await prisma.usernameHistory.count({
    where: { userId: session.sub },
  });
  const nextAllowedAt =
    priorChangeCount > 0 && user.usernameUpdatedAt
      ? new Date(
          user.usernameUpdatedAt.getTime() +
            USERNAME_CHANGE_COOLDOWN_DAYS * 24 * 60 * 60 * 1000,
        )
      : null;

  return NextResponse.json({
    username: user.username,
    usernameUpdatedAt: user.usernameUpdatedAt?.toISOString() ?? null,
    nextAllowedAt:
      nextAllowedAt && nextAllowedAt > new Date()
        ? nextAllowedAt.toISOString()
        : null,
  });
}

export async function PATCH(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk set username." },
      { status: 401 },
    );
  }

  const body = await request.json().catch(() => ({}));
  const rawInput = typeof body.username === "string" ? body.username : "";
  if (rawInput.trim().length === 0) {
    return NextResponse.json(
      { error: "Username wajib diisi." },
      { status: 400 },
    );
  }

  const formatError = validateUsernameFormat(rawInput);
  if (formatError) {
    return NextResponse.json(
      { error: formatError.message, code: formatError.code },
      { status: 400 },
    );
  }

  const normalized = normalizeUsername(rawInput);

  try {
    const result = await setUserUsername(session.sub, normalized);
    return NextResponse.json({ ok: true, username: result.username });
  } catch (error) {
    if (error instanceof UsernameCooldownError) {
      return NextResponse.json(
        {
          error: `Kamu bisa ganti username lagi pada ${error.nextAllowedAt.toLocaleDateString("id-ID", { day: "numeric", month: "long", year: "numeric" })}.`,
          code: "COOLDOWN",
          nextAllowedAt: error.nextAllowedAt.toISOString(),
        },
        { status: 429 },
      );
    }
    const message = error instanceof Error ? error.message : "UNKNOWN";
    if (message === "USERNAME_TAKEN") {
      return NextResponse.json(
        {
          error: "Username sudah dipakai. Coba yang lain.",
          code: "TAKEN",
        },
        { status: 409 },
      );
    }
    if (message === "USERNAME_RESERVED") {
      return NextResponse.json(
        {
          error:
            "Username ini baru saja dilepas oleh user lain. Coba lagi setelah masa reservasi (30 hari).",
          code: "RESERVED",
        },
        { status: 409 },
      );
    }
    if (message === "USER_NOT_FOUND") {
      return NextResponse.json(
        { error: "User tidak ditemukan." },
        { status: 404 },
      );
    }
    // Prisma unique constraint violation — race condition fallback.
    if (
      error &&
      typeof error === "object" &&
      "code" in error &&
      (error as { code: string }).code === "P2002"
    ) {
      return NextResponse.json(
        { error: "Username sudah dipakai. Coba yang lain.", code: "TAKEN" },
        { status: 409 },
      );
    }
    console.error("[/api/me/username PATCH] error:", error);
    return NextResponse.json(
      { error: "Gagal set username. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}
