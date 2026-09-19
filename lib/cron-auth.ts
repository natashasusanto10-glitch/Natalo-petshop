/**
 * Auth guard bersama untuk semua endpoint /api/cron/*.
 *
 * FAIL-CLOSED: kalau CRON_SECRET tidak ter-set (env hilang / typo saat
 * deploy) ATAU header Authorization tidak cocok → tolak dengan 403.
 * Sebelumnya beberapa route pakai pola `if (cronSecret && ...)` yang
 * membiarkan endpoint bisa dipanggil publik saat env var lupa diset.
 *
 * Vercel Cron otomatis mengirim `Authorization: Bearer $CRON_SECRET`
 * selama env var ter-set di project (lihat vercel.json → crons).
 *
 * Return `null` kalau authorized (caller lanjut), atau NextResponse 403
 * yang tinggal di-return caller:
 *
 *   const unauthorized = assertCronAuth(request);
 *   if (unauthorized) return unauthorized;
 */
import { NextResponse } from "next/server";

export function assertCronAuth(request: Request): NextResponse | null {
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret) {
    // Log sekali per request — berisik sengaja: konfigurasi hilang ini
    // harus kelihatan di log karena semua cron akan gagal sampai diset.
    console.error(
      "[cron-auth] CRON_SECRET tidak ter-set — request cron ditolak (fail-closed).",
    );
    return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  }
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  }
  return null;
}
