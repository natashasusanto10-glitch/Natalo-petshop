/**
 * AI-assisted product description generation via Claude API.
 *
 * Pakai: admin di halaman edit/create produk tap "✨ Generate deskripsi"
 * → Claude riset produk lewat web search (situs resmi brand/distributor),
 * lalu tulis deskripsi Bahasa Indonesia dari fakta yang ditemukan +
 * konteks yang kita kirim (nama, kategori, brand, varian).
 *
 * Env:
 *   ANTHROPIC_API_KEY — Anthropic API key. Set di Vercel project
 *     settings → Environment Variables.
 *
 * Model: claude-sonnet-5 — tier yang mendukung server tool
 * `web_search_20260209` (dynamic filtering) dengan biaya jauh di bawah
 * Opus. Web search jalan di server Anthropic, jadi tak ada integrasi
 * mesin pencari yang perlu kita kelola sendiri.
 */
import Anthropic from "@anthropic-ai/sdk";

const MODEL_ID = "claude-sonnet-5";

/**
 * Pagar biaya DAN waktu: maks pencarian web per satu klik "Generate
 * deskripsi". Tiap pencarian adalah satu round-trip penuh ke model,
 * jadi angka ini yang paling menentukan lama request — 4 pencarian
 * menembus batas durasi fungsi Vercel, 2 masih cukup untuk menemukan
 * halaman resmi brand.
 */
const MAX_WEB_SEARCHES = 2;

/**
 * Web search bisa bikin model minta jeda (`stop_reason: "pause_turn"`).
 * Kita sambung otomatis, tapi dibatasi supaya satu klik tak pernah jadi
 * loop tak berujung.
 */
const MAX_PAUSE_RESUMES = 3;

const SYSTEM_PROMPT = `Kamu copywriter e-commerce senior untuk Natalo Petshop, toko hewan peliharaan & aquarium di Medan.

TUGAS: tulis deskripsi produk dalam Bahasa Indonesia yang akurat, informatif, dan meyakinkan.

RISET DULU: gunakan tool web_search (maksimal ${MAX_WEB_SEARCHES} kali) untuk mencari halaman resmi brand/produsen atau distributor resmi produk ini. Ambil fakta: komposisi/bahan utama, kandungan nutrisi, ukuran/kemasan, peruntukan (jenis & usia hewan), cara pakai atau dosis, dan negara asal. Utamakan situs resmi brand; marketplace hanya cadangan. Kalau hasil pencarian jelas bukan produk yang sama, abaikan.

ATURAN FAKTA: hanya tulis hal yang kamu temukan di sumber atau yang sudah ada di konteks produk. Kalau sesuatu tidak ditemukan, lewati saja — JANGAN mengarang. Dilarang: klaim medis/terapi, angka kandungan atau sertifikasi tanpa sumber, janji berlebihan, harga, stok, dan menyebut toko lain.

FORMAT KELUARAN: 100-180 kata. Paragraf pembuka 2-3 kalimat (produk ini apa dan untuk hewan seperti apa), lalu 3-6 poin diawali '- ' berisi keunggulan/kandungan/cara pakai, tutup satu kalimat tentang varian yang tersedia kalau ada. Teks polos saja: tanpa judul, tanpa tabel, tanpa markdown selain '- ', tanpa URL atau nama sumber, dan tanpa kalimat pembuka/penutup seperti 'Berikut deskripsinya'.`;

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
 * Call Claude API dengan konteks produk + web search, return deskripsi
 * plain-text. Throw GenerateDescriptionError kalau API error, missing
 * key, atau input invalid.
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

  const messages: Anthropic.MessageParam[] = [
    { role: "user", content: userMessage },
  ];

  let response: Anthropic.Message;
  for (let attempt = 0; ; attempt++) {
    try {
      response = await client.messages.create({
        model: MODEL_ID,
        // Output yang diminta 100-180 kata; plafon longgar tapi tidak
        // sampai mengundang model menulis panjang lalu kehabisan waktu.
        max_tokens: 1200,
        system: SYSTEM_PROMPT,
        tools: [
          {
            type: "web_search_20260209",
            name: "web_search",
            max_uses: MAX_WEB_SEARCHES,
            user_location: { type: "approximate", country: "ID" },
          },
        ],
        messages,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new GenerateDescriptionError(
        `Gagal call Claude API: ${message}`,
        "API_ERROR",
      );
    }

    // Riset web yang panjang bisa dijeda server; sambung dengan mengirim
    // balik seluruh content apa adanya (termasuk blok hasil pencarian).
    if (response.stop_reason !== "pause_turn") break;
    if (attempt >= MAX_PAUSE_RESUMES) {
      throw new GenerateDescriptionError(
        "Riset produk kelamaan dan berhenti di tengah. Coba ulang.",
        "API_ERROR",
      );
    }
    messages.push({ role: "assistant", content: response.content });
  }

  if (response.stop_reason === "refusal") {
    throw new GenerateDescriptionError(
      "Claude menolak menulis deskripsi untuk produk ini. Tulis manual atau ubah nama produk.",
      "REFUSED",
    );
  }

  const cleaned = extractDescriptionText(response.content);
  if (!cleaned) {
    throw new GenerateDescriptionError(
      "Response Claude kosong. Coba ulang.",
      "EMPTY_RESPONSE",
    );
  }

  return cleaned;
}

/**
 * Gabungkan teks deskripsi dari content blocks.
 *
 * Dengan web search, `content` berisi campuran blok `server_tool_use`,
 * `web_search_tool_result`, dan BEBERAPA blok `text` (model memecah teks
 * per sitasi) — jadi gabungkan semua text block, jangan ambil yang
 * pertama seperti waktu belum ada tool. Fence markdown dibuang defensif.
 */
export function extractDescriptionText(
  content: Anthropic.ContentBlock[],
): string {
  return content
    .filter((block): block is Anthropic.TextBlock => block.type === "text")
    .map((block) => block.text)
    .join("")
    .trim()
    .replace(/^```(?:\w+)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
}
