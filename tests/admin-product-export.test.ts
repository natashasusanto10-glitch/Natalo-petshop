import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  EXPORT_COLUMNS,
  buildExportRows,
  variantLabel,
  type ExportProduct,
} from "@/lib/admin/product-export";

function produk(over: Partial<ExportProduct> = {}): ExportProduct {
  return {
    name: "Whiskas Tuna 1KG",
    slug: "whiskas-tuna-1kg",
    sku: "WSK-001",
    brandName: "Whiskas",
    categoryName: "Makanan Kucing",
    price: 50000,
    discountPrice: null,
    memberPrice: null,
    flashSaleEndsAt: null,
    stock: 12,
    weightGram: 1000,
    isActive: true,
    creationState: "ready",
    hasVariants: false,
    variants: [],
    ...over,
  };
}

describe("ekspor produk gaya Shopee", () => {
  it("tanpa varian: satu baris, harga/stok dari produk", () => {
    const rows = buildExportRows([produk()]);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].varian, "");
    assert.equal(rows[0].harga, 50000);
    assert.equal(rows[0].stok, 12);
    assert.equal(rows[0].skuProduk, "WSK-001");
    assert.equal(rows[0].link, "https://natalopetshop.com/products/whiskas-tuna-1kg");
  });

  it("bervarian: SATU BARIS PER VARIAN, TANPA baris induk", () => {
    // Baris induk produk bervarian selalu ber-stok 0 (stok asli hidup per
    // varian) — baris 0 palsu itu yang menyesatkan stok opname, jadi
    // ketiadaannya adalah perilaku inti, bukan kebetulan.
    const rows = buildExportRows([
      produk({
        hasVariants: true,
        stock: 0,
        variants: [
          {
            sku: "WSK-S",
            price: 48000,
            stock: 7,
            weightGram: 900,
            isActive: true,
            options: [
              { value: "Salmon", attributeName: "Rasa", attributePosition: 0 },
            ],
          },
          {
            sku: "WSK-T",
            price: 52000,
            stock: 3,
            weightGram: 1100,
            isActive: true,
            options: [
              { value: "Tuna", attributeName: "Rasa", attributePosition: 0 },
            ],
          },
        ],
      }),
    ]);
    assert.equal(rows.length, 2);
    assert.deepEqual(
      rows.map((r) => [r.varian, r.harga, r.stok, r.skuVarian]),
      [
        ["Rasa: Salmon", 48000, 7, "WSK-S"],
        ["Rasa: Tuna", 52000, 3, "WSK-T"],
      ],
    );
    // SKU produk (namespace terpisah dari SKU varian) tetap ada di tiap baris.
    assert.ok(rows.every((r) => r.skuProduk === "WSK-001"));
    // Tidak ada baris ber-stok 0 dari induk.
    assert.ok(rows.every((r) => r.stok > 0));
  });

  it("label varian multi-atribut urut posisi atribut, bukan urutan data", () => {
    const label = variantLabel([
      { value: "1KG", attributeName: "Ukuran", attributePosition: 1 },
      { value: "Salmon", attributeName: "Rasa", attributePosition: 0 },
    ]);
    assert.equal(label, "Rasa: Salmon, Ukuran: 1KG");
  });

  it("status: varian nonaktif jujur; produk nonaktif menular ke barisnya", () => {
    const rows = buildExportRows([
      produk({
        hasVariants: true,
        variants: [
          {
            sku: null,
            price: 1,
            stock: 1,
            weightGram: 1,
            isActive: false,
            options: [],
          },
        ],
      }),
      produk({ slug: "b", isActive: false }),
    ]);
    assert.equal(rows[0].status, "Nonaktif");
    assert.equal(rows[1].status, "Nonaktif");
  });

  it("field kosong jadi string kosong, bukan 'null'", () => {
    const rows = buildExportRows([
      produk({ sku: null, brandName: null, categoryName: null }),
    ]);
    assert.equal(rows[0].skuProduk, "");
    assert.equal(rows[0].brand, "");
    assert.equal(rows[0].kategori, "");
    assert.equal(rows[0].flashSaleBerakhir, "");
  });

  it("flash sale diformat tanggal-jam pendek DALAM WIB", () => {
    const rows = buildExportRows([
      produk({
        discountPrice: 40000,
        flashSaleEndsAt: new Date("2026-09-01T13:00:00Z"),
      }),
    ]);
    assert.equal(rows[0].hargaDiskon, 40000);
    // 13:00 UTC = 20:00 WIB — zona toko, bukan UTC. Regresi #review: versi
    // pertama mengekspor UTC dan tes ini sempat MENGUNCI data yang salah
    // 7 jam.
    assert.equal(rows[0].flashSaleBerakhir, "2026-09-01 20:00");
  });

  it("kolom worksheet dan kunci baris sinkron — kolom yatim = sel kosong diam-diam", () => {
    const row = buildExportRows([produk()])[0];
    for (const col of EXPORT_COLUMNS) {
      assert.ok(col.key in row, `kolom '${col.header}' tak punya data`);
    }
  });

  it("hasVariants=true tapi nol varian hidup: fallback DIBERI PENANDA", () => {
    // Semua varian soft-deleted -> baris jatuh ke harga/stok dasar yang utk
    // produk bervarian lazimnya 0. Tanpa penanda, terbaca "produk gratis
    // stok kosong" — persis baris menyesatkan yang desain ini hindari.
    const rows = buildExportRows([
      produk({ hasVariants: true, stock: 0, price: 0, variants: [] }),
    ]);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].varian, "(semua varian terhapus)");
  });

  it("produk nonaktif menular ke baris varian yang aktif", () => {
    const rows = buildExportRows([
      produk({
        isActive: false,
        hasVariants: true,
        variants: [
          { sku: null, price: 1, stock: 1, weightGram: 1, isActive: true, options: [] },
        ],
      }),
    ]);
    assert.equal(rows[0].status, "Nonaktif");
  });

  it("creationState bukan ready -> status Draft, MENGALAHKAN Aktif", () => {
    // Produk stuck "creating" (kelas insiden nyata di repo) tak boleh
    // terhitung sebagai stok sehat di lembar opname.
    const rows = buildExportRows([
      produk({ creationState: "creating", isActive: true }),
    ]);
    assert.equal(rows[0].status, "Draft (belum jadi)");
  });

  it("katalog kosong -> array kosong", () => {
    assert.deepEqual(buildExportRows([]), []);
  });

  it("label varian stabil saat dua atribut berbagi position", () => {
    const a = variantLabel([
      { value: "1KG", attributeName: "Ukuran", attributePosition: 0 },
      { value: "Salmon", attributeName: "Rasa", attributePosition: 0 },
    ]);
    const b = variantLabel([
      { value: "Salmon", attributeName: "Rasa", attributePosition: 0 },
      { value: "1KG", attributeName: "Ukuran", attributePosition: 0 },
    ]);
    assert.equal(a, b);
    assert.equal(a, "Rasa: Salmon, Ukuran: 1KG");
  });

  it("siteUrl parameter menimpa basis link", () => {
    const rows = buildExportRows([produk()], "https://staging.example.com");
    assert.equal(
      rows[0].link,
      "https://staging.example.com/products/whiskas-tuna-1kg",
    );
  });
});
