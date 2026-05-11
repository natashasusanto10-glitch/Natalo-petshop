import assert from "node:assert/strict";
import test from "node:test";
import {
  filterSortPaginateSearchDocs,
  type ProductSearchDoc,
  type SearchOptions,
} from "@/lib/search";
import { buildKeywordOnlySearchParams } from "@/lib/search-url";

function doc(overrides: Partial<ProductSearchDoc>): ProductSearchDoc {
  return {
    id: "product-1",
    slug: "product-1",
    name: "Royal Canin Persian Adult",
    description: "Makanan kucing persian",
    category_id: "cat-food",
    category_slug: "makanan-kucing",
    category_name: "Makanan Kucing",
    brand_id: "royal-canin",
    brand_slug: "royal-canin",
    brand_name: "Royal Canin",
    variant_names: [],
    sku_codes: [],
    price_min: 120000,
    price_max: 120000,
    discount_price: null,
    stock: 5,
    total_stock: 5,
    weight_grams: 500,
    avg_rating: 4.8,
    review_count: 12,
    created_at: 1_700_000_000,
    image_url: null,
    is_active: true,
    has_variants: false,
    ...overrides,
  };
}

const docs: ProductSearchDoc[] = [
  doc({
    id: "royal-persian-adult",
    slug: "royal-persian-adult",
    name: "Royal Canin Persian Adult 2kg",
    price_min: 125000,
    price_max: 125000,
    stock: 7,
    total_stock: 7,
    created_at: 1_700_000_100,
  }),
  doc({
    id: "royal-persian-kitten",
    slug: "royal-persian-kitten",
    name: "Royal Canin Persian Kitten 400g",
    price_min: 69000,
    price_max: 69000,
    stock: 4,
    total_stock: 4,
    created_at: 1_700_000_200,
  }),
  doc({
    id: "royal-persian-empty",
    slug: "royal-persian-empty",
    name: "Royal Canin Persian Adult Pouch",
    price_min: 18000,
    price_max: 18000,
    stock: 0,
    total_stock: 0,
    created_at: 1_700_000_300,
  }),
  doc({
    id: "proplan-persian",
    slug: "proplan-persian",
    name: "Pro Plan Persian Cat Food",
    brand_id: "pro-plan",
    brand_slug: "pro-plan",
    brand_name: "Pro Plan",
    price_min: 155000,
    price_max: 155000,
    stock: 8,
    total_stock: 8,
    created_at: 1_700_000_400,
  }),
  doc({
    id: "kandang-besi",
    slug: "kandang-besi",
    name: "Kandang Besi Lipat Kucing",
    description: "Kandang kuat untuk kucing dan anjing kecil",
    category_id: "cages",
    category_slug: "kandang",
    category_name: "Kandang",
    brand_id: null,
    brand_slug: null,
    brand_name: null,
    price_min: 210000,
    price_max: 210000,
    stock: 3,
    total_stock: 3,
    created_at: 1_700_000_500,
  }),
];

function search(overrides: Partial<SearchOptions>) {
  return filterSortPaginateSearchDocs(docs, {
    q: "",
    categorySlug: [],
    brandSlug: [],
    sort: "relevance",
    page: 1,
    perPage: 24,
    ...overrides,
  });
}

test("search only returns matching products and matching count", () => {
  const result = search({ q: "royal canin persian" });

  assert.equal(result.total, 3);
  assert.deepEqual(
    result.items.map((item) => item.id),
    ["royal-persian-empty", "royal-persian-kitten", "royal-persian-adult"],
  );
});

test("search plus brand filter uses the same filtered count and items", () => {
  const result = search({ q: "persian", brandSlug: ["royal-canin"] });

  assert.equal(result.total, 3);
  assert.equal(result.items.every((item) => item.brand_slug === "royal-canin"), true);
  assert.equal(result.facets.brands[0].slug, "royal-canin");
  assert.equal(result.facets.brands[0].count, 3);
});

test("search plus stock filter excludes out of stock products server side", () => {
  const result = search({ q: "royal canin persian", inStock: true });

  assert.equal(result.total, 2);
  assert.equal(result.items.some((item) => item.id === "royal-persian-empty"), false);
});

test("search plus price filter uses the same result set for count and items", () => {
  const result = search({ q: "persian", minPrice: 60000, maxPrice: 130000 });

  assert.equal(result.total, 2);
  assert.deepEqual(
    result.items.map((item) => item.id).sort(),
    ["royal-persian-adult", "royal-persian-kitten"],
  );
});

test("reset filter keeps only the keyword and drops filter, sort, and page params", () => {
  const current = new URLSearchParams(
    "q=royal+canin+persian&brand=royal-canin&in_stock=true&sort=price_desc&page=3",
  );
  const reset = buildKeywordOnlySearchParams(current.get("q") ?? "");

  assert.equal(reset.toString(), "q=royal+canin+persian");
  assert.equal(reset.has("brand"), false);
  assert.equal(reset.has("in_stock"), false);
  assert.equal(reset.has("sort"), false);
  assert.equal(reset.has("page"), false);
});

test("sort by lowest price orders products by ascending price", () => {
  const result = search({ q: "royal canin persian", sort: "price_asc" });

  assert.deepEqual(
    result.items.map((item) => item.id),
    ["royal-persian-empty", "royal-persian-kitten", "royal-persian-adult"],
  );
});

test("sort by highest price orders products by descending price", () => {
  const result = search({ q: "royal canin persian", sort: "price_desc" });

  assert.deepEqual(
    result.items.map((item) => item.id),
    ["royal-persian-adult", "royal-persian-kitten", "royal-persian-empty"],
  );
});

test("empty stock product does not appear when inStock is true", () => {
  const result = search({ q: "pouch", inStock: true });

  assert.equal(result.total, 0);
  assert.equal(result.items.length, 0);
});

test("partial and typo tolerant search can match kandang bsi to kandang besi", () => {
  const result = search({ q: "kandang bsi" });

  assert.equal(result.total, 1);
  assert.equal(result.items[0].id, "kandang-besi");
});
