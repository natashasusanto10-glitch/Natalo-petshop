import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getSwipeBackRouteConfig } from "../lib/swipe-back-routes";

describe("getSwipeBackRouteConfig", () => {
  it("disables swipe back on root bottom navigation pages", () => {
    for (const pathname of ["/", "/products", "/kategori", "/feed", "/member"]) {
      assert.equal(getSwipeBackRouteConfig(pathname).enableSwipeBack, false);
    }
  });

  it("enables swipe back on detail and inner pages", () => {
    for (const pathname of [
      "/products/royal-canin-adult",
      "/search",
      "/wishlist",
      "/akun/alamat/tambah",
      "/notifications/abc123",
      "/feed/upload",
    ]) {
      assert.equal(getSwipeBackRouteConfig(pathname).enableSwipeBack, true);
    }
  });

  it("keeps final checkout and order success pages protected", () => {
    for (const pathname of [
      "/checkout",
      "/payment/midtrans",
      "/pesanan/INV-001/success",
    ]) {
      assert.equal(getSwipeBackRouteConfig(pathname).enableSwipeBack, false);
    }
  });

  it("allows safe checkout substeps", () => {
    assert.equal(getSwipeBackRouteConfig("/checkout/addresses").enableSwipeBack, true);
  });
});
