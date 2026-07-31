import assert from "node:assert/strict";
import test from "node:test";
import {
  PRODUCTS_DEFAULT_SORT,
  buildApiSearchParams,
  buildProductsHref,
  parseProductsParams,
} from "@/lib/products-search-params";

function parse(query: string) {
  return parseProductsParams(new URLSearchParams(query));
}

test("empty url falls back to the owner-chosen default sort", () => {
  const p = parse("");
  assert.equal(p.sort, "best_seller");
  assert.equal(PRODUCTS_DEFAULT_SORT, "best_seller");
  assert.equal(p.page, 1);
  assert.deepEqual(p.categorySlugs, []);
  assert.equal(p.discountOnly, false);
});

test("kategori is the canonical param and maps to the api category param", () => {
  const p = parse("kategori=makanan-kucing");
  assert.deepEqual(p.categorySlugs, ["makanan-kucing"]);
  assert.equal(buildApiSearchParams(p).getAll("category").join(","), "makanan-kucing");
});

test("english category param is still accepted for external bookmarks", () => {
  assert.deepEqual(parse("category=makanan-anjing").categorySlugs, ["makanan-anjing"]);
});

test("kategori wins when both spellings are present", () => {
  assert.deepEqual(parse("kategori=a&category=b").categorySlugs, ["a"]);
});

test("legacy popular values translate to real sorts", () => {
  assert.equal(parse("popular=best-seller").sort, "best_seller");
  assert.equal(parse("popular=trending").sort, "trending");
  assert.equal(parse("popular=highest-rating").sort, "rating_desc");
  assert.equal(parse("popular=most-searched").sort, "best_seller");
  assert.equal(parse("popular=most-bought").sort, "best_seller");
});

test("every legacy new value collapses to newest", () => {
  for (const value of ["today", "this-week", "this-month", "last-30-days", "newest"]) {
    assert.equal(parse(`new=${value}`).sort, "newest", value);
  }
});

test("dead nav aliases now do what their label promises", () => {
  assert.equal(parse("sort=terlaris").sort, "best_seller");
  assert.equal(parse("sort=baru").sort, "newest");

  const promo = parse("sort=promo");
  assert.equal(promo.discountOnly, true);
  assert.equal(promo.sort, "best_seller");
});

test("dead promo flags now filter to discounted products", () => {
  assert.equal(parse("promo=1").discountOnly, true);
  assert.equal(parse("diskon=1").discountOnly, true);
  assert.equal(parse("discount_only=true").discountOnly, true);
});

test("explicit modern sort beats a legacy param", () => {
  assert.equal(parse("sort=price_asc&popular=best-seller").sort, "price_asc");
});

test("unknown sort falls back to the default instead of breaking", () => {
  assert.equal(parse("sort=bogus").sort, "best_seller");
});

test("multi brand and the numeric filters survive a round trip", () => {
  const p = parse("brand=royal-canin&brand=whiskas&min_price=50000&max_price=90000&in_stock=true&min_rating=4&page=3");
  assert.deepEqual(p.brandSlugs, ["royal-canin", "whiskas"]);
  assert.equal(p.minPrice, 50000);
  assert.equal(p.maxPrice, 90000);
  assert.equal(p.inStock, true);
  assert.equal(p.minRating, 4);
  assert.equal(p.page, 3);

  const api = buildApiSearchParams(p);
  assert.deepEqual(api.getAll("brand"), ["royal-canin", "whiskas"]);
  assert.equal(api.get("min_price"), "50000");
  assert.equal(api.get("in_stock"), "true");
  assert.equal(api.get("min_rating"), "4");
  assert.equal(api.get("page"), "3");
  assert.equal(api.get("per_page"), "24");
});

test("api params omit filters that are not set", () => {
  const api = buildApiSearchParams(parse(""));
  assert.equal(api.get("min_price"), null);
  assert.equal(api.get("in_stock"), null);
  assert.equal(api.get("discount_only"), null);
  assert.equal(api.get("q"), null);
});

test("discountOnly reaches the api as discount_only", () => {
  assert.equal(buildApiSearchParams(parse("promo=1")).get("discount_only"), "true");
});

test("href writes kategori back, never the english spelling", () => {
  const href = buildProductsHref(parse("category=makanan-ikan"));
  assert.ok(href.startsWith("/products?"), href);
  assert.ok(href.includes("kategori=makanan-ikan"), href);
  assert.ok(!href.includes("category="), href);
});

test("href drops the default sort and page 1 to keep urls clean", () => {
  assert.equal(buildProductsHref(parse("")), "/products");
  assert.equal(buildProductsHref(parse("page=1")), "/products");
  assert.ok(buildProductsHref(parse("sort=newest")).includes("sort=newest"));
});

test("href never carries the legacy params forward", () => {
  const href = buildProductsHref(parse("popular=best-seller&new=today&promo=1"));
  assert.ok(!href.includes("popular="), href);
  assert.ok(!href.includes("new="), href);
  assert.ok(!href.includes("promo="), href);
  assert.ok(href.includes("discount_only=true"), href);
});
