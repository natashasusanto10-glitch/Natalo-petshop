/**
 * AI-assisted voucher suggestion via Claude API.
 *
 * Pakai: admin di /admin/vouchers/new tap "✨ Buat dengan AI", isi
 * deskripsi natural language ("Promo Imlek 5 hari, 20% off makanan
 * kucing, min 100rb, max potong 50rb"), system call Claude → return
 * structured voucher config yang auto-fill form.
 *
 * Env:
 *   ANTHROPIC_API_KEY — Anthropic API key. Set di Vercel project
 *     settings → Environment Variables.
 *
 * Cost: ~$0.005/request (Sonnet 4.5). 20-50 voucher/bulan = negligible.
 *
 * Model: claude-sonnet-4-5 — match Natalo's existing usage standard
 * (lihat CLAUDE.md kalau ada model preference).
 */
import Anthropic from "@anthropic-ai/sdk";
import { prisma } from "@/lib/prisma";

const MODEL_ID = "claude-sonnet-4-5";

const SYSTEM_PROMPT = `Kamu adalah AI asisten untuk admin Natalo Petshop (e-commerce + social pet shop di Medan, Indonesia). Tugas: convert deskripsi promo natural language jadi JSON voucher config.

Output STRICT JSON tanpa text lain, dengan schema:
{
  "name": string,           // Display name voucher, max 60 char. Bahasa Indonesia. Contoh: "Diskon Imlek 20%"
  "code": string,           // Kode voucher SCREAMING_SNAKE_CASE, max 20 char. Contoh: "IMLEK2026"
  "description": string,    // Penjelasan customer-facing, max 140 char.
  "type": "PUBLIC_PRODUCT_DISCOUNT" | "PUBLIC_FREE_SHIPPING" | "PRIVATE_MANUAL_CODE",
  "discountType": "FIXED_AMOUNT" | "PERCENTAGE",
  "discountAmount": number | null,    // Rp value kalau FIXED_AMOUNT, null kalau PERCENTAGE
  "discountPercent": number | null,   // 1-90 kalau PERCENTAGE, null kalau FIXED_AMOUNT
  "maxDiscountAmount": number | null, // Cap discount maks (rupiah) — relevant untuk PERCENTAGE. Null = no cap.
  "minimumOrder": number,             // Min belanja rupiah. >= 0.
  "maxUsage": number | null,          // Total cap pemakaian (semua user). null = unlimited.
  "usageLimitPerUser": number,        // Default 1 (sekali per user). Boleh 2-5 untuk repeat.
  "expiresAt": string,                // ISO datetime kapan voucher expire. Default 30 hari dari sekarang kalau user gak spesifik.
  "targetUser": "ALL_MEMBERS" | "NEW_MEMBER", // NEW_MEMBER = user yang belum pernah order.
  "reasoning": string                 // 1-2 kalimat jelasin kenapa config ini sesuai prompt. Indonesia.
}

Rules:
- Kalau user gak spesifik nominal/persen, default ke PERCENTAGE 10%.
- Kalau user bilang "diskon X persen" tanpa cap, set maxDiscountAmount=null kecuali user spesifik.
- Kalau user bilang "min belanja X", set minimumOrder=X.
- Kalau user gak spesifik berapa hari, default 30 hari expire.
- Kalau prompt menyebut "gratis ongkir" → type=PUBLIC_FREE_SHIPPING (discountType FIXED_AMOUNT dengan discountAmount cap ongkir, mis. 30000).
- Code generate dari konteks (e.g. "Imlek" → "IMLEK", "ulang tahun Natalo" → "BDAY-NATALO"). Append tahun kalau seasonal (IMLEK2026).
- Date: gunakan tahun sekarang sebagai default. Bulan/tanggal sesuai konteks ("Imlek 2026" Feb 17, dll).

Output HANYA JSON, no markdown fence, no explanation outside.`;

export type AIVoucherSuggestion = {
  name: string;
  code: string;
  description: string;
  type: string;
  discountType: string;
  discountAmount: number | null;
  discountPercent: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  maxUsage: number | null;
  usageLimitPerUser: number;
  expiresAt: string;
  targetUser: string;
  reasoning: string;
};

export class AIVoucherSuggestError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = "AIVoucherSuggestError";
  }
}

/**
 * Build context for Claude — top 10 popular categories untuk suggestion
 * lebih relevan. Optional: existing voucher codes (anti-collision).
 */
async function buildContext(): Promise<string> {
  const [categories, recentCodes] = await Promise.all([
    prisma.category.findMany({
      select: { name: true, slug: true },
      take: 30,
    }),
    prisma.voucher.findMany({
      orderBy: { createdAt: "desc" },
      select: { code: true },
      take: 20,
    }),
  ]);

  return `Context Natalo:
- Kategori aktif: ${categories.map((c) => c.name).join(", ")}
- Kode voucher recent (HINDARI duplicate): ${recentCodes.map((v) => v.code).join(", ")}
- Mata uang: Rupiah (IDR). Format nominal sebagai integer (e.g. 50000 = Rp50.000).
- Tanggal hari ini: ${new Date().toISOString().slice(0, 10)}`;
}

/**
 * Call Claude API dengan prompt user, return parsed voucher config.
 * Throw AIVoucherSuggestError kalau API error, missing key, atau
 * response JSON invalid.
 */
export async function suggestVoucherFromPrompt(
  userPrompt: string,
): Promise<AIVoucherSuggestion> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new AIVoucherSuggestError(
      "ANTHROPIC_API_KEY belum di-set di environment variables. Hubungi developer untuk setup.",
      "MISSING_KEY",
    );
  }

  if (userPrompt.trim().length < 10) {
    throw new AIVoucherSuggestError(
      "Prompt terlalu pendek. Jelaskan promo yang mau dibuat (mis. 'diskon 20% makanan kucing, min belanja 100rb').",
      "PROMPT_TOO_SHORT",
    );
  }

  if (userPrompt.length > 2000) {
    throw new AIVoucherSuggestError(
      "Prompt terlalu panjang (max 2000 karakter).",
      "PROMPT_TOO_LONG",
    );
  }

  const context = await buildContext();
  const client = new Anthropic({ apiKey });

  let response;
  try {
    response = await client.messages.create({
      model: MODEL_ID,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: `${context}\n\nDeskripsi promo:\n${userPrompt.trim()}`,
        },
      ],
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new AIVoucherSuggestError(
      `Gagal call Claude API: ${message}`,
      "API_ERROR",
    );
  }

  // Extract text from response. Claude returns content array, ambil
  // text block pertama.
  const firstBlock = response.content[0];
  if (!firstBlock || firstBlock.type !== "text") {
    throw new AIVoucherSuggestError(
      "Response Claude tidak punya text content.",
      "EMPTY_RESPONSE",
    );
  }
  const rawText = firstBlock.text.trim();

  // Strip markdown fence kalau model kasih (defensive — system prompt
  // udah suruh jangan, tapi sometimes model masih kasih).
  const cleaned = rawText
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();

  let parsed: AIVoucherSuggestion;
  try {
    parsed = JSON.parse(cleaned);
  } catch (err) {
    console.warn("[ai-voucher] JSON parse failed:", { rawText, err });
    throw new AIVoucherSuggestError(
      "Response Claude bukan JSON valid. Coba ulang dengan deskripsi lebih jelas.",
      "INVALID_JSON",
    );
  }

  // Validate required fields (defensive — kalau model miss).
  if (!parsed.name || !parsed.code || !parsed.type) {
    throw new AIVoucherSuggestError(
      "Response Claude tidak lengkap (missing name/code/type). Coba ulang.",
      "INCOMPLETE_RESPONSE",
    );
  }

  return parsed;
}
