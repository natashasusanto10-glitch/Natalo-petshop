import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { canUseSeededListing } from "../lib/product/seeded-listing";

describe("gate jalur pengurutan berseed halaman Produk", () => {
  it("daftar polos + seed → jalur berseed AKTIF", () => {
    // Ini request default app: halaman Produk tanpa filter apa pun.
    // Regresi yang dijaga: dulu gate ikut memeriksa inStockOnly, dan
    // karena app SELALU mengirim inStock=true, cabang ini tidak pernah
    // tercapai — urutan katalog beku createdAt desc tiap hari, PR #297
    // tidak berfungsi sama sekali di app.
    assert.equal(canUseSeededListing({ randomSeed: "2026-08-27" }), true);
  });

  it("inStockOnly BUKAN parameter gate — filter stok hidup di SQL", () => {
    // Kalau seseorang menambahkan kembali inStockOnly ke params lalu ke
    // gate, test daftar-polos di atas tidak akan menangkapnya (app-nya
    // yang mengirim true, bukan test). Kunci di sini: predikat tidak
    // boleh punya key itu sama sekali.
    // Literal langsung — WAJIB, excess-property check TS hanya menyala di
    // literal, tidak lewat variabel perantara. Kalau nanti seseorang
    // menambahkan inStockOnly ke SeededListingParams, directive di bawah
    // jadi "unused" dan `tsc` merah — itu jebakannya.
    const result = canUseSeededListing({
      randomSeed: "2026-08-27",
      // @ts-expect-error inStockOnly sengaja bukan bagian dari SeededListingParams
      inStockOnly: true,
    });
    assert.equal(result, true);
  });

  it("seed + discountOnly → jalur berseed MATI (lindungi Flash Sale)", () => {
    // SQL berseed tidak punya syarat diskon. Kalau kombinasi ini lolos,
    // halaman Flash Sale menampilkan SELURUH katalog — terbukti di
    // produksi: discountOnly=3 produk, +seed=shampoo & pasir kucing.
    assert.equal(
      canUseSeededListing({ randomSeed: "2026-08-27", discountOnly: true }),
      false
    );
  });

  it("seed + filter lain apa pun → jalur berseed MATI", () => {
    const blockers: Array<Record<string, unknown>> = [
      { category: "Makanan Kucing" },
      { brand: "Happy Cat" },
      { brands: ["Happy Cat", "Royal Canin"] },
      { search: "minkas" },
      { newFilter: "new" },
      { popularFilter: "best-seller" },
      { excludeIds: ["abc"] },
      { hasPriceOnly: true },
      { withImageOnly: true },
    ];
    for (const blocker of blockers) {
      assert.equal(
        canUseSeededListing({ randomSeed: "2026-08-27", ...blocker }),
        false,
        `harus mati dengan ${JSON.stringify(blocker)}`
      );
    }
  });

  it("list kosong tidak dihitung sebagai filter", () => {
    assert.equal(
      canUseSeededListing({
        randomSeed: "2026-08-27",
        brands: [],
        excludeIds: [],
      }),
      true
    );
  });

  it("tanpa seed → selalu mati", () => {
    assert.equal(canUseSeededListing({}), false);
    assert.equal(canUseSeededListing({ randomSeed: "" }), false);
  });
});
