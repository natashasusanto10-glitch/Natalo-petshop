/**
 * GET /api/me/username/check?username=asiong
 *
 * Live availability check buat Username setup form. Return:
 *   { available: true } — handle bebas dipake
 *   { available: false, reason: "TAKEN" | "RESERVED" | "INVALID_FORMAT" | "RESERVED_KEYWORD", message }
 *
 * Dipakai dari Flutter form: tiap user ketik (debounced ~300ms),
 * cek live → tampilkan checkmark hijau / X merah inline.
 *
 * Login required — supaya `excludeUserId` bisa kita pass, user
 * boleh cek handle current-nya sendiri sebagai "available" (tidak
 * konflik dengan dirinya).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import {
  validateUsernameFormat,
  checkUsernameAvailability,
  normalizeUsername,
} from "@/lib/username";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu." },
      { status: 401 },
    );
  }

  const raw = request.nextUrl.searchParams.get("username") ?? "";
  if (raw.trim().length === 0) {
    return NextResponse.json({
      available: false,
      reason: "INVALID_FORMAT",
      message: "Username wajib diisi.",
    });
  }

  const formatError = validateUsernameFormat(raw);
  if (formatError) {
    return NextResponse.json({
      available: false,
      reason: formatError.code === "RESERVED" ? "RESERVED_KEYWORD" : "INVALID_FORMAT",
      message: formatError.message,
    });
  }

  const normalized = normalizeUsername(raw);
  const result = await checkUsernameAvailability(normalized, session.sub);
  if (result.available) {
    return NextResponse.json({ available: true });
  }
  return NextResponse.json({
    available: false,
    reason: result.reason,
    message:
      result.reason === "TAKEN"
        ? "Username sudah dipakai. Coba yang lain."
        : "Username ini baru saja dilepas. Tunggu sampai masa reservasi 30 hari habis.",
  });
}
