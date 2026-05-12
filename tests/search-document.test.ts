import assert from "node:assert/strict";
import test from "node:test";
import { SEARCHABLE_ATTRIBUTES, productToSearchDoc } from "@/lib/search-document.mjs";

function product(overrides = {}) {
  return {
    id: "product-1",
    slug: "product-1",
    name: "Royal Canin Kitten",
    description: "Kitten food",
    categoryId: "cat-1",
    category: { slug: "cat-food", name: "Cat Food" },
    brandId: "brand-1",
    brand: { slug: "royal-canin", name: "Royal Canin" },
    price: 120000,
    discountPrice: 99000,
    stock: 5,
    weightGram: 500,
    avgRating: 4.5,
    reviewCount: 10,
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
    imageUrl: "/product.png",
    isActive: true,
    hasVariants: false,
    variants: [],
    ...overrides,
  };
}

test("product search mapper emits the full runtime ProductSearchDoc schema", () => {
  const doc = productToSearchDoc(product());

  assert.deepEqual(Object.keys(doc).sort(), [
    "avg_rating",
    "brand_id",
    "brand_name",
    "brand_slug",
    "category_id",
    "category_name",
    "category_slug",
    "created_at",
    "description",
    "discount_price",
    "has_variants",
    "id",
    "image_url",
    "is_active",
    "name",
    "price_max",
    "price_min",
    "review_count",
    "sku_codes",
    "slug",
    "stock",
    "total_stock",
    "variant_names",
    "weight_grams",
  ]);
  assert.equal(doc.discount_price, 99000);
  assert.equal(doc.stock, 5);
  assert.equal(doc.has_variants, false);
});

test("main product search excludes category and description fields", () => {
  assert.deepEqual(SEARCHABLE_ATTRIBUTES, [
    "name",
    "brand_name",
    "variant_names",
    "sku_codes",
  ]);
});

test("product search mapper derives variant price, stock, names, and sku from active variants", () => {
  const doc = productToSearchDoc(
    product({
      hasVariants: true,
      stock: 999,
      variants: [
        {
          sku: "active-small",
          price: 50000,
          stock: 3,
          deletedAt: null,
          isActive: true,
          options: [{ option: { value: "Small" } }],
        },
        {
          sku: "active-large",
          price: 75000,
          stock: 2,
          deletedAt: null,
          isActive: true,
          options: [{ option: { value: "Large" } }],
        },
        {
          sku: "inactive",
          price: 1000,
          stock: 100,
          deletedAt: null,
          isActive: false,
          options: [{ option: { value: "Inactive" } }],
        },
      ],
    }),
  );

  assert.equal(doc.price_min, 50000);
  assert.equal(doc.price_max, 75000);
  assert.equal(doc.stock, 5);
  assert.equal(doc.total_stock, 5);
  assert.equal(doc.has_variants, true);
  assert.deepEqual(doc.variant_names.sort(), ["Large", "Small"]);
  assert.deepEqual(doc.sku_codes.sort(), ["active-large", "active-small"]);
});
