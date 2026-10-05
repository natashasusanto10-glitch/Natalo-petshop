import assert from "node:assert/strict";
import test from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ProductSalesMeta } from "@/components/product/ProductSalesMeta";

test("sold quantity remains visible without a rating", () => {
  const html = renderToStaticMarkup(createElement(ProductSalesMeta, {
    soldCount: 1250, avgRating: 0, reviewCount: 0, showRating: false,
  }));
  assert.match(html, /1\.250 terjual/);
  assert.doesNotMatch(html, /ulasan/);
});

test("rating and sold quantities render together", () => {
  const html = renderToStaticMarkup(createElement(ProductSalesMeta, {
    soldCount: 147, avgRating: 4.8, reviewCount: 3, showRating: true,
  }));
  assert.match(html, /147 terjual/);
  assert.match(html, /4\.8/);
  assert.match(html, /3 ulasan/);
});

test("no sales or reviews leaves no empty metadata row", () => {
  assert.equal(renderToStaticMarkup(createElement(ProductSalesMeta, {
    avgRating: 0, reviewCount: 0, showRating: true,
  })), "");
});
