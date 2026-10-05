import assert from "node:assert/strict";
import { test } from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ProductVoucherBadges } from "@/components/product/ProductVoucherBadges";
import type { ProductVoucherPreview } from "@/lib/product-vouchers";

const discount: ProductVoucherPreview = {
  id: "discount", title: "Voucher Brand", description: null,
  badgeLabel: "Hemat s.d. Rp50.000", sheetTitle: "Diskon 10% hingga Rp50.000",
  sheetSubtitle: "Min. belanja Rp300.000", discountPercent: 10,
  discountAmount: null, maxDiscountAmount: 50000, minimumOrder: 300000,
  savingAmount: 50000, expiresAt: null, type: "PUBLIC_PRODUCT_DISCOUNT",
  discountScope: "PRODUCT", targetUser: "NEW_MEMBER", loginRequired: true,
  isBrandExclusive: true,
};
const shipping: ProductVoucherPreview = {
  ...discount, id: "shipping", badgeLabel: "Gratis Ongkir",
  type: "PUBLIC_FREE_SHIPPING", discountScope: "SHIPPING",
  sheetTitle: "Gratis Ongkir", targetUser: "ALL_MEMBERS",
};

test("no matching voucher produces no badge or placeholder", () => {
  assert.equal(renderToStaticMarkup(createElement(ProductVoucherBadges, {})), "");
});

test("discount and shipping use the system labels and show their conditions", () => {
  const html = renderToStaticMarkup(createElement(ProductVoucherBadges, {
    voucherPreview: discount, shippingVoucherPreview: shipping,
  }));
  assert.match(html, /Hemat s.d. Rp50.000/);
  assert.match(html, /Gratis Ongkir/);
  assert.match(html, /Min. belanja Rp300.000/);
  assert.match(html, /Khusus member baru/);
  assert.match(html, /data-voucher-scope="SHIPPING"/);
  assert.match(html, /data-voucher-scope="PRODUCT"/);
  assert.equal((html.match(/data-voucher-scope=/g) ?? []).length, 2);
});


test("product markdown shows savings even with only a shipping voucher", () => {
  const html = renderToStaticMarkup(createElement(ProductVoucherBadges, { savingsAmount: 2800, shippingVoucherPreview: shipping }));
  assert.match(html, /Hemat Rp(?:&nbsp;|&#xA0;| | )2.800/);
  assert.match(html, /Gratis Ongkir/);
});

test("product voucher label takes precedence over markdown savings, like Flutter", () => {
  const html = renderToStaticMarkup(createElement(ProductVoucherBadges, { savingsAmount: 2800, voucherPreview: discount }));
  assert.match(html, /Hemat s.d. Rp50.000/);
  assert.doesNotMatch(html, /2.800/);
});

test("shipping voucher alone does not claim product savings", () => {
  const html = renderToStaticMarkup(createElement(ProductVoucherBadges, { shippingVoucherPreview: shipping }));
  assert.match(html, /Gratis Ongkir/);
  assert.doesNotMatch(html, /Hemat/);
});
