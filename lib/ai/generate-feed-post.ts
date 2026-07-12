/**
 * AI-assisted feed post copy generation via Claude API.
 *
 * Pakai: admin di halaman "Buat Post Feed" tap "✨ Generate judul & caption"
 * → dari topik singkat + (opsional) produk yang di-tag → hasilkan judul
 * pendek + caption Bahasa Indonesia siap-posting.
 *
 * Env:
 *   ANTHROPIC_API_KEY — Anthropic API key (Vercel env vars).
 *
 * Model: claude-sonnet-4-5 — match standar repo (lihat
 * lib/ai/voucher-suggest.ts & lib/ai/generate-product-description.ts).
 */
import Anthropic from "@anthropic-ai/sdk";

const MODEL_ID = "claude-sonnet-4-5";

const SYSTEM_PROMPT = `Kamu penulis konten sosial feed untuk Natalo Petshop (toko hewan & aquarium di Medan). Tugas: dari topik + info produk (kalau ada), buat SATU judul singkat dan SATU caption untuk video feed.

Aturan judul: Bahasa Indonesia, 4-9 kata, memikat & jelas (ini juga dipakai sebagai headline notifikasi), TANPA tanda kutip, TANPA emoji berlebihan (maks 1 emoji, boleh tanpa emoji).

Aturan caption: Bahasa Indonesia, 1-3 kalimat pendek, ramah & mengajak, boleh 1-3 emoji relevan, boleh 1-3 hashtag di akhir (mis. #NataloPetshop). Kalau ada produk, sebut manfaat/ajakan yang wajar. JANGAN mengarang klaim medis/kesehatan yang tak pasti, harga/diskon yang tak diberikan, atau janji berlebihan.

Output WAJIB JSON valid persis: {"title": "...", "caption": "..."} — tanpa markdown fence, tanpa teks lain.`;

export type GenerateFeedPostInput = {
  /** Topik/kata kunci singkat dari admin (mis. "grooming kucing musim panas"). */
  topic?: string | null;
  /** Jenis post — beri konteks nada (edukasi vs jualan vs promo). */
  kind?: "VIDEO_ONLY" | "VIDEO_PRODUCT" | "PROMO" | null;
  /** Nama produk yang di-tag (kalau ada). */
  productNames?: string[];
};

export type GeneratedFeedPost = {
  title: string;
  caption: string;
};

export class GenerateFeedPostError extends Error {
  constructor(message: string, public readonly code: string) {
    super(message);
    this.name = "GenerateFeedPostError";
  }
}

function kindLabel(kind: GenerateFeedPostInput["kind"]): string {
  switch (kind) {
    case "VIDEO_PRODUCT":
      return "Video + Produk (konten yang menampilkan produk)";
    case "PROMO":
      return "Promo Produk (konten diskon/penawaran)";
    case "VIDEO_ONLY":
    default:
      return "Video Edukasi (konten edukasi/tips, tanpa jualan langsung)";
  }
}

/**
 * Call Claude API, return { title, caption }. Butuh minimal topik ATAU
 * satu produk sebagai bahan. Throw GenerateFeedPostError kalau API error,
 * key hilang, input kosong, atau response tak bisa di-parse.
 */
export async function generateFeedPost(
  input: GenerateFeedPostInput,
): Promise<GeneratedFeedPost> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new GenerateFeedPostError(
      "ANTHROPIC_API_KEY belum di-set di environment variables. Hubungi developer untuk setup.",
      "MISSING_KEY",
    );
  }

  const topic = (input.topic ?? "").trim();
  const productNames = (input.productNames ?? [])
    .map((n) => n.trim())
    .filter(Boolean);

  if (!topic && productNames.length === 0) {
    throw new GenerateFeedPostError(
      "Isi topik dulu atau tag minimal satu produk sebelum generate.",
      "INVALID_INPUT",
    );
  }

  const userMessage = `Jenis post: ${kindLabel(input.kind)}\nTopik: ${
    topic || "-"
  }\nProduk yang di-tag: ${productNames.length ? productNames.join(", ") : "-"}`;

  const client = new Anthropic({ apiKey });

  let response;
  try {
    response = await client.messages.create({
      model: MODEL_ID,
      max_tokens: 500,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userMessage }],
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new GenerateFeedPostError(
      `Gagal call Claude API: ${message}`,
      "API_ERROR",
    );
  }

  const firstBlock = response.content[0];
  if (!firstBlock || firstBlock.type !== "text") {
    throw new GenerateFeedPostError(
      "Response Claude tidak punya text content.",
      "EMPTY_RESPONSE",
    );
  }

  // Strip markdown fence defensif lalu parse JSON.
  const cleaned = firstBlock.text
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new GenerateFeedPostError(
      "Response Claude bukan JSON valid. Coba ulang.",
      "PARSE_ERROR",
    );
  }

  const obj = parsed as { title?: unknown; caption?: unknown };
  const title = typeof obj.title === "string" ? obj.title.trim() : "";
  const caption = typeof obj.caption === "string" ? obj.caption.trim() : "";

  if (!title || !caption) {
    throw new GenerateFeedPostError(
      "Response Claude tidak lengkap (judul/caption kosong). Coba ulang.",
      "EMPTY_RESPONSE",
    );
  }

  return { title, caption };
}
