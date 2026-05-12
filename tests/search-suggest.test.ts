import assert from "node:assert/strict";
import test from "node:test";
import { mergeSuggestionProducts, type SuggestProduct } from "@/lib/search-suggest";

function product(overrides: Partial<SuggestProduct>): SuggestProduct {
  return {
    id: "product-1",
    slug: "product-1",
    name: "Fresh DB Product",
    image_url: null,
    price_min: 10000,
    price_max: 10000,
    brand_name: null,
    ...overrides,
  };
}

test("search suggestions prefer fresh DB product data over stale Meilisearch data", () => {
  const products = mergeSuggestionProducts({
    dbProducts: [
      product({
        id: "product-1",
        slug: "fresh-slug",
        name: "Fresh DB Name",
        price_min: 25000,
        price_max: 25000,
      }),
    ],
    meiliProducts: [
      product({
        id: "product-1",
        slug: "stale-slug",
        name: "Stale Meili Name",
        price_min: 10000,
        price_max: 10000,
      }),
    ],
    limit: 5,
  });

  assert.equal(products.length, 1);
  assert.equal(products[0].slug, "fresh-slug");
  assert.equal(products[0].name, "Fresh DB Name");
  assert.equal(products[0].price_min, 25000);
});

test("search suggestions can append hydrated Meilisearch-only candidates after DB results", () => {
  const products = mergeSuggestionProducts({
    dbProducts: [product({ id: "db-product", name: "DB Match" })],
    meiliProducts: [product({ id: "meili-product", name: "Hydrated Meili Match" })],
    limit: 5,
  });

  assert.deepEqual(
    products.map((item) => item.id),
    ["db-product", "meili-product"],
  );
});
