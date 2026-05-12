import assert from "node:assert/strict";
import test from "node:test";
import {
  buildDbSearchPageArgs,
  buildMeiliSearchParams,
  type NormalizedSearchOptions,
} from "@/lib/search";

function opts(overrides: Partial<NormalizedSearchOptions> = {}): NormalizedSearchOptions {
  return {
    q: "royal canin",
    categorySlug: [],
    brandSlug: [],
    sort: "relevance",
    page: 1,
    perPage: 24,
    ...overrides,
  };
}

test("Meilisearch search params push filter, sort, and pagination into the index", () => {
  const params = buildMeiliSearchParams(
    opts({
      categorySlug: ["cat-food"],
      brandSlug: ["royal-canin"],
      minPrice: 50000,
      maxPrice: 200000,
      inStock: true,
      minRating: 4,
      sort: "price_asc",
      page: 3,
      perPage: 12,
    }),
  );

  assert.equal(params.q, "royal canin");
  assert.equal(params.limit, 12);
  assert.equal(params.offset, 24);
  assert.equal(params.candidateLimit >= params.offset + params.limit, true);
  assert.deepEqual(params.sort, ["price_min:asc"]);
  assert.match(params.filter, /is_active = true/);
  assert.match(params.filter, /category_slug = "cat-food"/);
  assert.match(params.filter, /brand_slug = "royal-canin"/);
  assert.match(params.filter, /price_min >= 50000/);
  assert.match(params.filter, /price_min <= 200000/);
  assert.match(params.filter, /total_stock > 0/);
  assert.match(params.filter, /avg_rating >= 4/);
});

test("database fallback query uses Prisma skip and take instead of full catalog pagination", () => {
  const args = buildDbSearchPageArgs(
    opts({
      brandSlug: ["royal-canin"],
      sort: "newest",
      page: 2,
      perPage: 10,
      inStock: true,
    }),
  );

  assert.equal(args.skip, 10);
  assert.equal(args.take, 10);
  assert.deepEqual(args.orderBy, [{ createdAt: "desc" }]);
  assert.equal(args.where.isActive, true);
  assert.deepEqual(args.where.brand, { slug: { in: ["royal-canin"] } });
  assert.ok("AND" in args.where);
});
