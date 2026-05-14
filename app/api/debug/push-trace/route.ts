import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";

/**
 * Debug endpoint untuk trace push subscription flow dari client.
 *
 * Client (lib/push-client.ts) POST event di tiap step:
 * - register-start
 * - permission-checked
 * - permission-requested
 * - register-denied
 * - register-complete
 * - register-error
 * - token-posted
 * - token-post-error
 *
 * Server hanya log ke Vercel Functions Logs — tidak persist ke DB.
 * Cara baca: Vercel dashboard → project → Logs tab → filter "/api/debug/push-trace".
 *
 * SAFETY: endpoint tidak butuh auth (supaya guest/pre-login step bisa di-trace).
 * Hanya log non-PII data (event name, platform, status code). Token preview
 * dari client sudah di-truncate ke 12 chars.
 *
 * TODO: Hapus endpoint ini saat push notification sudah stabil di production.
 */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return NextResponse.json({ ok: false }, { status: 400 });
  }

  // Sertakan session info kalau ada — bantu trace kasus "user tidak login".
  const session = await getSession("CUSTOMER").catch(() => null);
  const userTag = session?.sub ? `user:${session.sub.slice(-6)}` : "guest";

  // Single-line structured log untuk easy grep di Vercel Logs.
  console.log("[push-trace]", JSON.stringify({ ...body, userTag }));

  return NextResponse.json({ ok: true });
}
