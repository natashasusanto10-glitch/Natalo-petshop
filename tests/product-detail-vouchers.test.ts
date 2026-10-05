import assert from "node:assert/strict";
import { test } from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { VoucherCard, isVisibleProductVoucher, type VoucherItem } from "@/components/products/VoucherCard";

const voucher: VoucherItem = {
  id: "discount", title: "Voucher produk", description: null,
  type: "PUBLIC_PRODUCT_DISCOUNT", badgeLabel: "Hemat s.d. Rp50.000",
  sheetTitle: "Diskon 10% hingga Rp50.000", discountScope: "PRODUCT",
  discountPercent: 10, discountAmount: null, maxDiscountAmount: 50000,
  minimumOrder: 300000, expiresAt: null,
};

test("detail accepts public discount and shipping vouchers returned by its API", () => {
  const html = renderToStaticMarkup(createElement(VoucherCard, { vouchers: [voucher, {
    ...voucher, id: "shipping", type: "PUBLIC_FREE_SHIPPING", discountScope: "SHIPPING", badgeLabel: "Gratis Ongkir",
  }] }));
  assert.match(html, /Hemat s.d. Rp50.000/);
  assert.match(html, /Gratis Ongkir/);
  assert.match(html, /Min. belanja Rp300.000/);
  assert.match(html, /Lihat semua \(2\)/);
});

test("private, used, inactive and expired vouchers stay hidden", () => {
  for (const overrides of [{ isPrivate: true }, { usedByCurrentUser: true }, { isActive: false }, { expiresAt: "2020-01-01T00:00:00Z" }]) {
    assert.equal(isVisibleProductVoucher({ ...voucher, ...overrides }), false);
  }
  assert.equal(isVisibleProductVoucher({ ...voucher, type: "member" }), true);
});

test("base discount is visible even without a voucher, no offer renders nothing", () => {
  assert.match(renderToStaticMarkup(createElement(VoucherCard, { vouchers: [], savingsAmount: 2800 })), /Hemat Rp2.800/);
  assert.equal(renderToStaticMarkup(createElement(VoucherCard, { vouchers: [] })), "");
});
