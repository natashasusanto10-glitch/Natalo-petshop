import assert from "node:assert/strict";
import test from "node:test";
import { toCatalogCard } from "@/lib/chat/catalog-card";
import type { StoreProduct } from "@/lib/products";

const ALLOWLIST = [
  "brand",
  "discountPrice",
  "imageUrl",
  "isAvailable",
  "name",
  "price",
  "productId",
  "slug",
  "stock",
].sort();

function makeStoreProduct(overrides: Partial<StoreProduct> = {}): StoreProduct {
  return {
    id: "prod-1",
    name: "Royal Canin Kitten 2kg",
    slug: "royal-canin-kitten-2kg",
    description: "Makanan kucing kitten premium",
    price: 250000,
    discountPrice: null,
    memberPrice: 240000,
    stock: 10,
    weightGram: 2000,
    imageUrl: "https://cdn.natalopetshop.com/prod-1.jpg",
    gallery: ["https://cdn.natalopetshop.com/prod-1.jpg"],
    hasVariants: false,
    avgRating: 4.8,
    reviewCount: 120,
    soldCount: 500,
    categoryId: "cat-1",
    categorySlug: "makanan-kucing",
    brand: "Royal Canin",
    brandId: "brand-1",
    voucherPreview: { code: "HEMAT10", label: "Diskon 10%" } as never,
    shippingVoucherPreview: null,
    flashSaleEndsAt: null,
    ...overrides,
  };
}

test("toCatalogCard hanya mengembalikan field allowlist (tak ada field internal bocor)", () => {
  const product = makeStoreProduct();
  const card = toCatalogCard(product);
  assert.deepEqual(Object.keys(card).sort(), ALLOWLIST);
});

test("isAvailable true saat stock>0", () => {
  const card = toCatalogCard(makeStoreProduct({ stock: 5 }));
  assert.equal(card.isAvailable, true);
});

test("isAvailable false saat stock===0", () => {
  const card = toCatalogCard(makeStoreProduct({ stock: 0 }));
  assert.equal(card.isAvailable, false);
});

test("discountPrice null bila StoreProduct tak punya diskon aktif", () => {
  const card = toCatalogCard(makeStoreProduct({ discountPrice: null }));
  assert.equal(card.discountPrice, null);
});

test("discountPrice angka bila StoreProduct punya diskon aktif", () => {
  const card = toCatalogCard(makeStoreProduct({ discountPrice: 199000 }));
  assert.equal(card.discountPrice, 199000);
});

test("productId diambil dari p.id, field lain pass-through", () => {
  const product = makeStoreProduct({
    id: "prod-42",
    slug: "slug-42",
    name: "Nama Produk",
    price: 100000,
    stock: 7,
  });
  const card = toCatalogCard(product);
  assert.equal(card.productId, "prod-42");
  assert.equal(card.slug, "slug-42");
  assert.equal(card.name, "Nama Produk");
  assert.equal(card.price, 100000);
  assert.equal(card.stock, 7);
});

test("imageUrl dan brand null-safe bila StoreProduct tak set", () => {
  const card = toCatalogCard(
    makeStoreProduct({ imageUrl: null, brand: undefined }),
  );
  assert.equal(card.imageUrl, null);
  assert.equal(card.brand, null);
});
