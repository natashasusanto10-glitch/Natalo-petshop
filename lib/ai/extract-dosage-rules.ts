/**
 * AI-assisted dosage-rule extraction via Claude API.
 *
 * Pakai: admin di halaman edit/create produk obat cacing/kutu tap
 * "✨ Ekstrak aturan dosis dengan AI" → parse nama + deskripsi produk
 * jadi daftar aturan dosis terstruktur per rentang berat badan.
 *
 * Env:
 *   ANTHROPIC_API_KEY — Anthropic API key. Set di Vercel project
 *     settings → Environment Variables.
 *
 * Model: claude-sonnet-4-5 — match Natalo's existing usage standard
 * (lihat lib/ai/generate-product-description.ts).
 */
import Anthropic from "@anthropic-ai/sdk";
import { parseDosageRules, type DosageRule } from "@/lib/product-dosage";

const MODEL_ID = "claude-sonnet-4-5";

const SYSTEM_PROMPT = `Kamu asisten data untuk toko hewan. Dari info produk obat cacing/kutu, ekstrak aturan dosis per rentang berat badan hewan. Output HANYA JSON array valid, tanpa teks lain, format: [{"minKg": number, "maxKg": number|null, "instruction": string}]. minKg inklusif, maxKg eksklusif (null = tak terbatas ke atas). instruction singkat (mis. "1/2 tablet", "1 pipet ukuran S"). Kalau info tidak memuat aturan dosis apa pun, output persis: []`;

export class ExtractDosageError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = "ExtractDosageError";
  }
}

/**
 * Parse teks response model jadi JSON. Strip markdown fence kalau
 * model kasih (defensive — system prompt udah suruh jangan, tapi
 * sometimes model masih kasih). Return null kalau bukan JSON valid.
 */
export function parseModelJson(text: string): unknown {
  const cleaned = text
    .trim()
    .replace(/^```(?:\w+)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    return null;
  }
}

/**
 * Call Claude API dengan nama + deskripsi produk, return daftar
 * DosageRule terstruktur (bisa kosong kalau tidak ada aturan dosis).
 * Throw ExtractDosageError kalau API error atau missing key.
 */
export async function extractDosageRulesFromText(input: {
  name: string;
  description: string;
}): Promise<DosageRule[]> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new ExtractDosageError("ANTHROPIC_API_KEY belum di-set.", "MISSING_KEY");
  }
  const client = new Anthropic({ apiKey });
  let response;
  try {
    response = await client.messages.create({
      model: MODEL_ID,
      max_tokens: 500,
      system: SYSTEM_PROMPT,
      messages: [
        { role: "user", content: `Nama: ${input.name}\nDeskripsi:\n${input.description}` },
      ],
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new ExtractDosageError(`Gagal call Claude API: ${message}`, "API_ERROR");
  }
  const first = response.content[0];
  if (!first || first.type !== "text") return [];
  return parseDosageRules(parseModelJson(first.text));
}
