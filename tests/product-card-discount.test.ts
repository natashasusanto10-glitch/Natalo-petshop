import test from "node:test";
import assert from "node:assert/strict";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import type { StoreProduct } from "../lib/products";
import { ProductCard, computeDiscountPercent } from "../components/ProductCard";

test("normal markdown rounds up, min 1", () => {
  assert.equal(computeDiscountPercent(100000, 90000), 10);
  assert.equal(computeDiscountPercent(100000, 99900), 1); // <1% floors to 1
});

test("no markdown or zero price yields 0", () => {
  assert.equal(computeDiscountPercent(100000, 100000), 0);
  assert.equal(computeDiscountPercent(0, 0), 0);
});

const product: StoreProduct = { id: "test", slug: "test", name: "Test product", description: "", price: 28000, discountPrice: 25200, stock: 5, weightGram: 100, imageUrl: null, gallery: [], hasVariants: false, avgRating: 0, reviewCount: 0 };

test("discounted grid price is red, crossed price and savings are visible", () => {
  const html = renderToStaticMarkup(createElement(ProductCard, { product, preview: true }));
  assert.match(html, /text-\[#E11D48\][^>]*>Rp[^<]*25.200/);
  assert.match(html, /line-through[^>]*>Rp[^<]*28.000/);
  assert.match(html, /Hemat Rp[^<]*2.800/);
});

test("ordinary grid price stays blue without a savings claim", () => {
  const html = renderToStaticMarkup(createElement(ProductCard, { product: { ...product, discountPrice: null }, preview: true }));
  assert.match(html, /text-\[#1E5FBF\][^>]*>Rp[^<]*28.000/);
  assert.doesNotMatch(html, /Hemat|line-through/);
});
