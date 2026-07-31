import assert from "node:assert/strict";
import test from "node:test";
import { searchDocToStoreProduct } from "@/lib/search-doc-to-product";
import type { ProductSearchDoc } from "@/lib/search";

function searchDoc(overrides: Partial<ProductSearchDoc> = {}): ProductSearchDoc {
  return {
    id: "p1",
    slug: "royal-canin-persian",
    name: "Royal Canin Persian Adult",
    description: "Makanan kucing persian",
    category_id: "c1",
    category_slug: "makanan-kucing",
    category_name: "Makanan Kucing",
    brand_id: "b1",
    brand_slug: "royal-canin",
    brand_name: "Royal Canin",
    variant_names: [],
    sku_codes: [],
    price_min: 120_000,
    price_max: 120_000,
    discount_price: null,
    member_price: null,
    stock: 5,
    total_stock: 5,
    weight_grams: 500,
    avg_rating: 4.8,
    review_count: 12,
    created_at: 1_700_000_000,
    image_url: "https://example.test/a.jpg",
    is_active: true,
    has_variants: false,
    ...overrides,
  };
}

test("maps the fields the product card actually reads", () => {
  const p = searchDocToStoreProduct(searchDoc());

  assert.equal(p.id, "p1");
  assert.equal(p.slug, "royal-canin-persian");
  assert.equal(p.name, "Royal Canin Persian Adult");
  assert.equal(p.price, 120_000);
  assert.equal(p.discountPrice, null);
  assert.equal(p.stock, 5);
  assert.equal(p.imageUrl, "https://example.test/a.jpg");
  assert.equal(p.hasVariants, false);
  assert.equal(p.avgRating, 4.8);
  assert.equal(p.reviewCount, 12);
});

test("member price survives the mapping so the Member pill still renders", () => {
  const p = searchDocToStoreProduct(searchDoc({ member_price: 99_000 }));
  assert.equal(p.memberPrice, 99_000);
});

test("no member price maps to null, not undefined", () => {
  assert.equal(searchDocToStoreProduct(searchDoc()).memberPrice, null);
});

test("discount price is carried through for the discount badge", () => {
  const p = searchDocToStoreProduct(searchDoc({ price_min: 100_000, discount_price: 75_000 }));
  assert.equal(p.price, 100_000);
  assert.equal(p.discountPrice, 75_000);
});

test("stock falls back to total_stock when the per-product field is zero", () => {
  const p = searchDocToStoreProduct(searchDoc({ stock: 0, total_stock: 7 }));
  assert.equal(p.stock, 7);
});

test("weight gets the same maxi-cat correction the products api applies", () => {
  const p = searchDocToStoreProduct(
    searchDoc({
      name: "Maxi-Cat Premium Cat Food 20kg",
      slug: "maxi-cat-premium-cat-food-20kg",
      weight_grams: 1000,
    }),
  );
  assert.equal(p.weightGram, 20_000);
});

test("ordinary products keep their own weight", () => {
  assert.equal(searchDocToStoreProduct(searchDoc({ weight_grams: 850 })).weightGram, 850);
});

test("brand and category labels come across for downstream use", () => {
  const p = searchDocToStoreProduct(searchDoc());
  assert.equal(p.brand, "Royal Canin");
  assert.equal(p.brandId, "b1");
  assert.equal(p.categorySlug, "makanan-kucing");
});

test("gallery is an empty array so consumers never hit undefined", () => {
  assert.deepEqual(searchDocToStoreProduct(searchDoc()).gallery, []);
});
