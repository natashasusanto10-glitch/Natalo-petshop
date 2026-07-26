import test from "node:test";
import assert from "node:assert/strict";
import {
  buildUsageMaps,
  composeUsed,
  toShoppingProduct,
  SUGGESTED_LIMIT,
  inStockCandidates,
  orderRowsByIds,
  toStockCandidate,
} from "../app/api/member/pets/[id]/shopping/route";
import type { ProductRow } from "../app/api/member/pets/[id]/shopping/route";

const d = (s: string) => new Date(s);

test("used: dedup per produk, hitung pemakaian, ambil doneAt terbaru", () => {
  const { used, manual } = buildUsageMaps([
    { productId: "p1", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "p1", brandText: null, doneAt: d("2026-04-01T00:00:00Z") },
    { productId: "p2", brandText: null, doneAt: d("2026-06-01T00:00:00Z") },
  ]);
  assert.equal(used.size, 2);
  assert.equal(used.get("p1")!.usageCount, 2);
  assert.deepEqual(used.get("p1")!.lastUsedAt, d("2026-07-01T00:00:00Z"));
  assert.equal(manual.size, 0);
});

test("manual: brandText di-trim, dedup, record tanpa brand diabaikan", () => {
  const { used, manual } = buildUsageMaps([
    { productId: null, brandText: " Bravecto ", doneAt: d("2026-07-01T00:00:00Z") },
    { productId: null, brandText: "Bravecto", doneAt: d("2026-05-01T00:00:00Z") },
    { productId: null, brandText: "   ", doneAt: d("2026-05-01T00:00:00Z") },
    { productId: null, brandText: null, doneAt: d("2026-05-01T00:00:00Z") },
  ]);
  assert.equal(used.size, 0);
  assert.equal(manual.size, 1);
  assert.equal(manual.get("Bravecto")!.usageCount, 2);
  assert.deepEqual(manual.get("Bravecto")!.lastUsedAt, d("2026-07-01T00:00:00Z"));
});

test("toShoppingProduct: stok varian dihitung dari variants, bukan Product.stock", () => {
  const out = toShoppingProduct({
    id: "p1",
    slug: "drontal-cat",
    name: "Drontal Cat",
    imageUrl: "https://cdn/x.jpg",
    price: 45000,
    stock: 0,
    targetSpecies: [],
    category: { name: "Obat & Suplemen" },
    variants: [{ price: 47000, stock: 3 }],
  });
  assert.equal(out.productId, "p1");
  assert.equal(out.slug, "drontal-cat");
  assert.equal(out.hasVariants, true);
  assert.equal(out.inStock, true, "produk varian base stock 0 tetap in-stock");
});

test("toShoppingProduct: produk non-varian pakai stok & harga sendiri", () => {
  const out = toShoppingProduct({
    id: "p2",
    slug: "sisir",
    name: "Sisir Grooming",
    imageUrl: null,
    price: 19500,
    stock: 0,
    targetSpecies: [],
    category: null,
    variants: [],
  });
  assert.equal(out.hasVariants, false);
  assert.equal(out.inStock, false);
  assert.equal(out.effectivePrice, 19500);
});

const row = (id: string, slug: string) => ({
  id,
  slug,
  name: id,
  imageUrl: null,
  price: 1000,
  stock: 5,
  targetSpecies: [] as string[],
  category: null,
  variants: [] as { price: number; stock: number }[],
});

test("composeUsed: produk nonaktif (tak ada di rows) hilang dari daftar", () => {
  const { used } = buildUsageMaps([
    { productId: "p1", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "gone", brandText: null, doneAt: d("2026-06-01T00:00:00Z") },
  ]);
  // `rows` hanya berisi p1 — meniru query `isActive: true` yang membuang "gone".
  const out = composeUsed([row("p1", "s1")], used);
  assert.equal(out.length, 1);
  assert.equal(out[0].productId, "p1");
});

test("composeUsed: urut terakhir-dipakai lebih dulu", () => {
  const { used } = buildUsageMaps([
    { productId: "baru", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "lama", brandText: null, doneAt: d("2026-01-01T00:00:00Z") },
  ]);
  const out = composeUsed([row("lama", "s-lama"), row("baru", "s-baru")], used);
  assert.deepEqual(out.map((o) => o.productId), ["baru", "lama"]);
});

test("INVARIAN: usedCount == jumlah baris yang tampil, walau ada produk nonaktif", () => {
  const { used, manual } = buildUsageMaps([
    { productId: "p1", brandText: null, doneAt: d("2026-07-01T00:00:00Z") },
    { productId: "gone", brandText: null, doneAt: d("2026-06-01T00:00:00Z") },
    { productId: null, brandText: "Bravecto", doneAt: d("2026-05-01T00:00:00Z") },
  ]);
  const usedList = composeUsed([row("p1", "s1")], used);
  const usedCount = usedList.length + manual.size;
  assert.equal(usedCount, 2, "1 produk aktif + 1 brand manual; yang nonaktif tak dihitung");
});

test("SUGGESTED_LIMIT = 12 (grid), rail memakai 6 pertama", () => {
  assert.equal(SUGGESTED_LIMIT, 12);
});

test("toStockCandidate: produk varian base stock 0 tetap in-stock", () => {
  const out = toStockCandidate({
    id: "p1",
    stock: 0,
    targetSpecies: [],
    category: { name: "Makanan Anjing" },
    variants: [{ stock: 4 }],
  });
  assert.equal(out.inStock, true, "stok varian WAJIB dijumlahkan");
  assert.equal(out.categoryName, "Makanan Anjing");
  assert.deepEqual(out.targetSpecies, []);
});

test("toStockCandidate: produk tanpa kategori → categoryName null", () => {
  const out = toStockCandidate({
    id: "p2",
    stock: 3,
    targetSpecies: [],
    category: null,
    variants: [],
  });
  assert.equal(out.categoryName, null);
  assert.equal(out.inStock, true);
});

test("inStockCandidates: item habis dibuang SEBELUM seleksi", () => {
  // Kalau filter stok terjadi SESUDAH seleksi, permintaan 12 slot bisa
  // menghasilkan 7 kartu — slot bocor tanpa sebab yang terlihat user.
  const out = inStockCandidates([
    {
      id: "ada",
      stock: 2,
      targetSpecies: [],
      category: { name: "Makanan Anjing" },
      variants: [],
    },
    {
      id: "habis",
      stock: 0,
      targetSpecies: [],
      category: { name: "Makanan Anjing" },
      variants: [],
    },
    {
      id: "varian-habis",
      stock: 0,
      targetSpecies: [],
      category: { name: "Snack Anjing" },
      variants: [{ stock: 0 }],
    },
  ]);
  assert.deepEqual(out.map((c) => c.id), ["ada"]);
});

test("orderRowsByIds: urutan hasil mengikuti urutan id, bukan urutan DB", () => {
  const row = (id: string): ProductRow => ({
    id,
    slug: id,
    name: id,
    imageUrl: null,
    price: 1000,
    stock: 5,
    targetSpecies: [],
    category: { name: "Makanan Anjing" },
    variants: [],
  });
  const out = orderRowsByIds([row("c"), row("a"), row("b")], ["b", "c", "a"]);
  assert.deepEqual(out.map((r) => r.id), ["b", "c", "a"]);
});

test("orderRowsByIds: id tanpa baris (produk hilang) dilewati diam-diam", () => {
  const row = (id: string): ProductRow => ({
    id,
    slug: id,
    name: id,
    imageUrl: null,
    price: 1000,
    stock: 5,
    targetSpecies: [],
    category: null,
    variants: [],
  });
  const out = orderRowsByIds([row("a")], ["a", "hilang"]);
  assert.deepEqual(out.map((r) => r.id), ["a"]);
});
