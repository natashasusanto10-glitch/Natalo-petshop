/**
 * Kategori voucher untuk kartu statistik halaman admin.
 *
 * Dulu halaman /admin/vouchers menarik SELURUH baris voucher lalu menghitung
 * keempat kategorinya di JavaScript. Itu tidak bisa dipertahankan: voucher
 * loyalty dibuat PER PENGGUNA (ulang tahun, klaim poin), jadi jumlah barisnya
 * tumbuh mengikuti jumlah member, bukan jumlah campaign.
 *
 * Menerjemahkan seluruh klasifikasi ke SQL berisiko: aturannya akan hidup di
 * dua tempat dan melenceng. Jadi hanya SATU predikat yang diterjemahkan —
 * "apakah ini voucher loyalty" — sisanya tetap memakai fungsi JS yang sama
 * seperti sebelumnya, hanya dijalankan atas hasil `groupBy` yang berisi
 * segelintir baris, bukan atas seluruh tabel.
 */

/** Cerminan SQL dari `isLoyaltyClaimVoucher()` di lib/voucher-kind.ts. */
export const LOYALTY_VOUCHER_WHERE = {
  // Literal `as const` per nilai (BUKAN `as const` pada objeknya): tipe enum
  // Prisma menolak `string` biasa, sementara `as const` di level objek membuat
  // arraynya readonly dan Prisma menolak itu juga.
  OR: [
    { kind: "LOYALTY_CLAIM" as const },
    { userId: { not: null } },
    { code: { startsWith: "POIN-" } },
  ],
};

/**
 * Kebalikan persis dari atas. Ketiga syarat harus gagal sekaligus, karena
 * negasi dari (A atau B atau C) adalah (bukan A dan bukan B dan bukan C).
 */
export const NON_LOYALTY_VOUCHER_WHERE = {
  kind: { not: "LOYALTY_CLAIM" as const },
  userId: null,
  NOT: { code: { startsWith: "POIN-" } },
};

export type VoucherCategory =
  | "PRODUCT_DISCOUNT"
  | "FREE_SHIPPING"
  | "LOYALTY_CLAIM"
  | "MANUAL_PRIVATE";

/**
 * Kategori untuk voucher yang SUDAH dipastikan bukan loyalty.
 * Urutan cabangnya sengaja sama persis dengan rantai if/else lama.
 */
export function nonLoyaltyCategory(
  kind: string | null,
  sourceType: string | null,
): Exclude<VoucherCategory, "LOYALTY_CLAIM"> {
  if (kind === "FREE_SHIPPING") return "FREE_SHIPPING";
  if (kind === "MANUAL_PRIVATE" || sourceType === "SELLER_MANUAL") {
    return "MANUAL_PRIVATE";
  }
  return "PRODUCT_DISCOUNT";
}

export type VoucherGroupRow = {
  kind: string | null;
  sourceType: string | null;
  _count: number;
};

/** Rakit keempat angka kartu dari satu hitungan loyalty + hasil groupBy. */
export function tallyVoucherCategories(
  loyaltyCount: number,
  groups: VoucherGroupRow[],
): Record<VoucherCategory, number> {
  const counts: Record<VoucherCategory, number> = {
    PRODUCT_DISCOUNT: 0,
    FREE_SHIPPING: 0,
    LOYALTY_CLAIM: loyaltyCount,
    MANUAL_PRIVATE: 0,
  };
  for (const group of groups) {
    counts[nonLoyaltyCategory(group.kind, group.sourceType)] += group._count;
  }
  return counts;
}
