/**
 * AI-assisted product description generation via Claude API.
 *
 * Pakai: admin di halaman edit/create produk tap "✨ Buat deskripsi
 * dengan AI" → generate deskripsi produk Bahasa Indonesia dari nama +
 * kategori + brand + varian produk.
 *
 * Env:
 *   ANTHROPIC_API_KEY — Anthropic API key. Set di Vercel project
 *     settings → Environment Variables.
 *
 * Model: claude-sonnet-4-5 — match Natalo's existing usage standard
 * (lihat lib/ai/voucher-suggest.ts).
 */
import Anthropic from "@anthropic-ai/sdk";

const MODEL_ID = "claude-sonnet-4-5";

const SYSTEM_PROMPT = `Kamu penulis deskripsi produk untuk Natalo Petshop (toko hewan & aquarium di Medan). Tulis deskripsi produk dalam Bahasa Indonesia yang informatif + persuasif ringan: sorot manfaat/keunggulan produk, sebut varian kalau ada, panjang ~80-150 kata, boleh pakai beberapa poin pendek (pakai '- ' di awal baris). JANGAN mengarang klaim medis/kesehatan yang tak pasti, angka/sertifikasi palsu, atau janji berlebihan. Output HANYA teks deskripsi — tanpa judul, tanpa markdown fence, tanpa kalimat pembuka seperti 'Berikut deskripsinya'.`;

export type GenerateProductDescriptionInput = {
  name: string;
  categoryName?: string | null;
  brandName?: string | null;
  variantOptions?: string[];
};

export class GenerateDescriptionError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = "GenerateDescriptionError";
  }
}

/**
 * Call Claude API dengan konteks produk, return deskripsi plain-text.
 * Throw GenerateDescriptionError kalau API error, missing key, atau
 * input invalid.
 */
export async function generateProductDescription(
  input: GenerateProductDescriptionInput,
): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new GenerateDescriptionError(
      "ANTHROPIC_API_KEY belum di-set di environment variables. Hubungi developer untuk setup.",
      "MISSING_KEY",
    );
  }

  const name = input.name.trim();
  if (!name) {
    throw new GenerateDescriptionError(
      "Nama produk wajib diisi sebelum generate deskripsi.",
      "INVALID_INPUT",
    );
  }

  const userMessage = `Nama produk: ${name}\nKategori: ${input.categoryName ?? "-"}\nBrand: ${input.brandName ?? "-"}\nVarian: ${
    input.variantOptions?.length ? input.variantOptions.join(", ") : "-"
  }`;

  const client = new Anthropic({ apiKey });

  let response;
  try {
    response = await client.messages.create({
      model: MODEL_ID,
      max_tokens: 600,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: userMessage,
        },
      ],
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new GenerateDescriptionError(
      `Gagal call Claude API: ${message}`,
      "API_ERROR",
    );
  }

  // Extract text from response. Claude returns content array, ambil
  // text block pertama.
  const firstBlock = response.content[0];
  if (!firstBlock || firstBlock.type !== "text") {
    throw new GenerateDescriptionError(
      "Response Claude tidak punya text content.",
      "EMPTY_RESPONSE",
    );
  }
  const rawText = firstBlock.text.trim();

  // Strip markdown fence kalau model kasih (defensive — system prompt
  // udah suruh jangan, tapi sometimes model masih kasih).
  const cleaned = rawText
    .replace(/^```(?:\w+)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();

  if (!cleaned) {
    throw new GenerateDescriptionError(
      "Response Claude kosong. Coba ulang.",
      "EMPTY_RESPONSE",
    );
  }

  return cleaned;
}
