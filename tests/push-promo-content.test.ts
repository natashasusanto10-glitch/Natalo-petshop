import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildVoucherPromoContent,
  buildDiscountPromoContent,
  maxDiscountPercent,
  isPromoDue,
} from "../lib/push-promo-content";

test("voucher gratis ongkir → eventType freeship + judul truk", () => {
  const r = buildVoucherPromoContent({
    code: "ONGKIRGRATIS",
    name: null,
    kind: "FREE_SHIPPING",
    discountPercent: null,
    discountAmount: null,
  });
  assert.equal(r.eventType, "voucher_freeship_published");
  assert.match(r.title, /Gratis Ongkir/i);
  assert.match(r.body, /ONGKIRGRATIS/);
});

test("voucher diskon persen → eventType discount + sebut persen & kode", () => {
  const r = buildVoucherPromoContent({
    code: "HEMAT20",
    name: "Hemat Juli",
    kind: "PRODUCT_DISCOUNT",
    discountPercent: 20,
    discountAmount: null,
  });
  assert.equal(r.eventType, "voucher_discount_published");
  assert.match(r.body, /20%/);
  assert.match(r.body, /HEMAT20/);
});

test("voucher diskon nominal → body sebut Rp", () => {
  const r = buildVoucherPromoContent({
    code: "POTONG5RB",
    name: null,
    kind: "PRODUCT_DISCOUNT",
    discountPercent: null,
    discountAmount: 5000,
  });
  assert.equal(r.eventType, "voucher_discount_published");
  assert.match(r.body, /Rp\s?5.?000/);
});

test("diskon 1 produk → url slug + judul nama produk", () => {
  const r = buildDiscountPromoContent(
    { name: "Promo Kucing" },
    [
      {
        product: { name: "Royal Canin 2kg", slug: "royal-canin-2kg", imageUrl: "https://cdn/rc.jpg", price: 200000 },
        variant: null,
        discountedPrice: 150000,
      },
    ],
  );
  assert.equal(r.url, "/produk/royal-canin-2kg");
  assert.equal(r.thumbnailUrl, "https://cdn/rc.jpg");
  assert.match(r.title, /Royal Canin 2kg/);
  assert.match(r.body, /25%/); // (200000-150000)/200000 = 25%
});

test("diskon banyak produk → url katalog + hitung persen tertinggi", () => {
  const r = buildDiscountPromoContent(
    { name: "Promo Toko" },
    [
      { product: { name: "A", slug: "a", imageUrl: "https://cdn/a.jpg", price: 100000 }, variant: null, discountedPrice: 90000 }, // 10%
      { product: { name: "B", slug: "b", imageUrl: null, price: 100000 }, variant: null, discountedPrice: 60000 }, // 40%
    ],
  );
  assert.equal(r.url, "/products");
  assert.equal(r.thumbnailUrl, "https://cdn/a.jpg");
  assert.match(r.body, /40%/);
});

test("maxDiscountPercent: harga varian dipakai bila ada; harga asli 0 dilewati", () => {
  assert.equal(
    maxDiscountPercent([
      { product: { price: 0 }, variant: { price: 50000 }, discountedPrice: 25000 }, // varian 50%
      { product: { price: 0 }, variant: null, discountedPrice: 10000 }, // asli 0 → skip
    ]),
    50,
  );
});

test("maxDiscountPercent: semua tak valid → null", () => {
  assert.equal(
    maxDiscountPercent([
      { product: { price: 100 }, variant: null, discountedPrice: 100 }, // 0% skip
    ]),
    null,
  );
});

test("isPromoDue: aktif, mulai lewat, belum notif → true", () => {
  const now = new Date("2026-07-19T10:00:00Z");
  assert.equal(
    isPromoDue(
      { notifyAtStart: true, promoNotifiedAt: null, isActive: true, startsAt: new Date("2026-07-19T09:00:00Z"), endsAt: new Date("2026-07-25T00:00:00Z") },
      now,
    ),
    true,
  );
});

test("isPromoDue: sudah ter-notif / belum mulai / sudah berakhir → false", () => {
  const now = new Date("2026-07-19T10:00:00Z");
  const base = { notifyAtStart: true, isActive: true, startsAt: new Date("2026-07-19T09:00:00Z"), endsAt: null };
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: new Date() }, now), false);
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: null, startsAt: new Date("2026-07-20T00:00:00Z") }, now), false);
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: null, endsAt: new Date("2026-07-19T00:00:00Z") }, now), false);
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: null, notifyAtStart: false }, now), false);
});
