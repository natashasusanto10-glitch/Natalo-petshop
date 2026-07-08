import { createHash } from "crypto";

/**
 * Rotasi rekomendasi ber-seed — supaya section "Ayoo diborong bossku" tidak
 * menampilkan produk yang itu-itu saja tiap buka. Seed di-pin per kunjungan
 * (stabil dalam satu buka → pagination konsisten; beda antar-buka → fresh).
 *
 * Murni (tanpa DB) supaya bisa diuji. Dipakai oleh
 * app/api/recommendations/personalized/route.ts.
 */

// Hash deterministik dari (id, seed). Dipakai sebagai kunci urut acak-tapi-stabil.
export function seededHash(id: string, seed: string): string {
  return createHash("md5").update(`${id}::${seed}`).digest("hex");
}

// Urutan acak deterministik berdasarkan seed. Seed kosong → urutan input apa
// adanya (backward-compat: caller lama tanpa seed berperilaku persis seperti dulu).
export function seededShuffle<T extends { id: string }>(items: T[], seed: string): T[] {
  if (!seed) return [...items];
  return [...items].sort((a, b) => {
    const ha = seededHash(a.id, seed);
    const hb = seededHash(b.id, seed);
    return ha < hb ? -1 : ha > hb ? 1 : 0;
  });
}

// Urutkan kandidat ber-skor:
//  - Anchor (mis. voucher repurchase "saatnya beli ulang") SELALU di depan,
//    diurut skor desc — jangan pernah dikubur rotasi karena time-sensitive.
//  - Sisanya: tanpa seed → murni skor desc (backward-compat); dengan seed →
//    dirotasi DALAM tier skor kasar (item yang jelas lebih relevan tetap di
//    depan, tapi yang setara berputar antar-kunjungan). Menjaga relevansi
//    sekaligus kesegaran.
export function orderScoredCandidates<T extends { id: string }>(
  scored: Array<{ product: T; score: number }>,
  opts: { seed: string; isAnchor: (product: T) => boolean; tierStep?: number },
): Array<{ product: T; score: number }> {
  const tierStep = opts.tierStep ?? 0.5;
  const anchors = scored
    .filter((s) => opts.isAnchor(s.product))
    .sort((a, b) => b.score - a.score);
  const rest = scored.filter((s) => !opts.isAnchor(s.product));
  if (opts.seed) {
    rest.sort((a, b) => {
      const tierA = Math.round(a.score / tierStep);
      const tierB = Math.round(b.score / tierStep);
      if (tierA !== tierB) return tierB - tierA;
      const ha = seededHash(a.product.id, opts.seed);
      const hb = seededHash(b.product.id, opts.seed);
      return ha < hb ? -1 : ha > hb ? 1 : 0;
    });
  } else {
    rest.sort((a, b) => b.score - a.score);
  }
  return [...anchors, ...rest];
}
