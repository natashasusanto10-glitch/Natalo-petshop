/**
 * Hashtag (Spec C) — SATU sumber aturan parsing, di-mirror persis di
 * flutter_app/lib/utils/mention_text.dart. Ubah di sini ⇒ ubah di sana.
 *
 * Boundary: '#' hanya valid di awal teks atau setelah whitespace —
 * "harga#promo" dan "natalo.com/#promo" BUKAN tag (spec §1).
 */
const HASHTAG_SOURCE = /(^|\s)#([a-z0-9_]+)/gi;

export const MAX_HASHTAGS_PER_POST = 5;
export const HASHTAG_LIMIT_MESSAGE = "Maksimal 5 hashtag per postingan.";

const MIN_NAME_LENGTH = 2;
const MAX_NAME_LENGTH = 50;

/** Nama kanonik: lowercase [a-z0-9_], panjang 2-50, tanpa '#'. */
export function isValidHashtagName(name: string): boolean {
  if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
    return false;
  }
  return /^[a-z0-9_]+$/.test(name);
}

/**
 * Extract hashtag dari teks caption: lowercase, dedup (sekali hitung),
 * urutan kemunculan pertama, filter panjang 2-50 (filter di fungsi, bukan
 * regex — pola sama extractMentionHandles di lib/feed/mentions.ts).
 */
export function extractHashtags(text: string): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const match of text.matchAll(HASHTAG_SOURCE)) {
    const name = match[2].toLowerCase();
    if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
      continue;
    }
    if (seen.has(name)) continue;
    seen.add(name);
    result.push(name);
  }
  return result;
}
