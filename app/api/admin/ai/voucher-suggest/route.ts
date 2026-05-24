/**
 * POST /api/admin/ai/voucher-suggest
 *
 * AI-generate voucher config dari natural language prompt admin.
 * Body: { prompt: string }
 * Response: { suggestion: AIVoucherSuggestion } atau { error, code }.
 *
 * Auth: ADMIN role only.
 * Rate limit: 20 req/jam per admin (anti abuse / runaway cost).
 * Audit: logged via logAdminAction (action = AI_VOUCHER_SUGGEST).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import {
  suggestVoucherFromPrompt,
  AIVoucherSuggestError,
} from "@/lib/ai/voucher-suggest";
import { logAdminAction } from "@/lib/admin-audit";
import { checkLimit, getClientIp, getOtpLimiter } from "@/lib/rate-limit";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Rate limit — pakai OTP limiter infra existing (per-admin, per-hour).
  // Reuse limiter supaya gak overkill bikin limiter baru.
  const ip = getClientIp(request.headers);
  const rateKey = `ai-voucher:${session.sub}:${ip}`;
  const gate = await checkLimit(getOtpLimiter(), rateKey);
  if (!gate.ok) {
    return NextResponse.json(
      {
        error: "Terlalu banyak request AI. Coba lagi nanti.",
        retryAfterSec: gate.retryAfter,
      },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } },
    );
  }

  const body = await request.json().catch(() => null);
  const prompt = body && typeof body.prompt === "string" ? body.prompt : "";

  try {
    const suggestion = await suggestVoucherFromPrompt(prompt);

    logAdminAction({
      actorUserId: session.sub,
      action: "AI_VOUCHER_SUGGEST",
      targetType: "Voucher",
      targetId: "(suggestion-only)",
      summary: `AI voucher suggest: "${prompt.slice(0, 80)}${prompt.length > 80 ? "…" : ""}"`,
      metadata: {
        promptLength: prompt.length,
        suggestedCode: suggestion.code,
        suggestedType: suggestion.type,
      },
    });

    return NextResponse.json({ ok: true, suggestion });
  } catch (err) {
    if (err instanceof AIVoucherSuggestError) {
      const status = err.code === "MISSING_KEY" ? 500
        : err.code === "API_ERROR" ? 502
        : 400;
      return NextResponse.json(
        { error: err.message, code: err.code },
        { status },
      );
    }
    console.error("[ai-voucher] unexpected error:", err);
    return NextResponse.json(
      { error: "Gagal generate suggestion. Coba lagi.", code: "UNKNOWN" },
      { status: 500 },
    );
  }
}
