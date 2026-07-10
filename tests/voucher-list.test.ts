/**
 * Tests untuk `buildVoucherListItems` — pure function yang handle filter
 * + transform voucher untuk listing endpoint.
 *
 * Cover: bug yang menjadi alasan helper ini dibuat + edge cases yang
 * pernah miss di endpoint lama.
 *
 * Lihat juga: lib/voucher-list.ts (doc lengkap business rules).
 */
import assert from "node:assert/strict";
import test from "node:test";
import type { Voucher } from "@prisma/client";
import { buildVoucherListItems } from "@/lib/voucher-list";
import type {
  VoucherUsageOrder,
  VoucherUserContext,
} from "@/lib/voucher-helpers";

const NOW = new Date("2026-05-24T12:00:00Z");

function voucher(overrides: Partial<Voucher>): Voucher {
  return {
    id: "v-default",
    name: null,
    code: "TEST",
    description: null,
    discountPercent: null,
    discountAmount: 10000,
    maxDiscountAmount: null,
    minimumOrder: 0,
    maxUsage: null,
    usedCount: 0,
    usageLimitPerUser: 1,
    usageLimitPeriod: "LIFETIME",
    startsAt: new Date("2026-01-01T00:00:00Z"),
    expiresAt: new Date("2026-12-31T23:59:59Z"),
    isActive: true,
    userId: null,
    sourceType: "CUSTOMER",
    type: "PUBLIC_PRODUCT_DISCOUNT",
    kind: "PRODUCT_DISCOUNT",
    visibility: "PUBLIC",
    discountType: "FIXED_AMOUNT",
    discountScope: "PRODUCT",
    targetUser: "ALL_MEMBERS",
    newMemberMaxAccountAgeDays: null,
    newMemberRequireNoSuccessfulOrder: false,
    eligibleUserIds: [],
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    eligibleBrandIds: [],
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  } as Voucher;
}

function userCtx(overrides: Partial<VoucherUserContext> = {}): VoucherUserContext {
  return {
    isLoggedIn: true,
    userId: "user-natsu",
    createdAt: new Date("2025-01-01T00:00:00Z"),
    successfulOrderCount: 0,
    ...overrides,
  };
}

// ─── BUG UTAMA: voucher publik admin (userId=null) HARUS tampil ──────

test("voucher publik admin (userId=null) tampil untuk SEMUA user", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({ id: "v-public", code: "PUBLIC", userId: null, minimumOrder: 0 }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 50000,
    now: NOW,
  });
  assert.equal(items.length, 1, "voucher publik harus muncul");
  assert.equal(items[0].code, "PUBLIC");
  assert.equal(items[0].applicable, true);
});

test("voucher owned (userId=X) hanya untuk user X — user lain TIDAK lihat", () => {
  const vouchers = [
    voucher({ id: "v-natsu", code: "NATSUONLY", userId: "user-natsu" }),
    voucher({ id: "v-hadi", code: "HADIONLY", userId: "user-hadi" }),
  ];
  // Tapi Prisma WHERE clause sudah filter di level DB pakai
  // `OR: [{userId: null}, {userId: session.sub}]` — fixture ini
  // simulasi voucher Natsu saja yang return ke helper.
  const items = buildVoucherListItems({
    vouchers: [vouchers[0]],
    userUsedOrders: [],
    userCtx: userCtx({ userId: "user-natsu" }),
    subtotal: 50000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].code, "NATSUONLY");
});

// ─── shouldHideVoucher: voucher PERMANENTLY tidak bisa dipakai ───────

test("voucher expired → hidden total (tidak muncul)", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-expired",
        code: "EXPIRED",
        expiresAt: new Date("2025-12-31T00:00:00Z"), // sebelum NOW
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 50000,
    now: NOW,
  });
  assert.equal(items.length, 0, "voucher expired harus hidden");
});

test("voucher inactive (isActive=false) → hidden total", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({ id: "v-inactive", code: "OFF", isActive: false }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 50000,
    now: NOW,
  });
  assert.equal(items.length, 0);
});

test("voucher max usage tercapai → hidden total", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-full",
        code: "FULL",
        maxUsage: 10,
        usedCount: 10,
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 50000,
    now: NOW,
  });
  assert.equal(items.length, 0);
});

test("voucher sudah dipakai user (per-user limit reach) → hidden total", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-used",
        code: "USED",
        usageLimitPerUser: 1,
        usageLimitPeriod: "LIFETIME",
      }),
    ],
    userUsedOrders: [
      {
        createdAt: new Date("2026-03-01T00:00:00Z"),
        voucherCode: "USED",
        freeShippingVoucherCode: null,
        productVoucherCode: null,
        shippingVoucherCode: null,
        loyaltyVoucherCode: null,
        manualVoucherCode: null,
        privateVoucherCode: null,
      },
    ],
    userCtx: userCtx(),
    subtotal: 50000,
    now: NOW,
  });
  assert.equal(items.length, 0, "user sudah pakai → tidak boleh lagi");
});

// ─── eligibleUserIds whitelist — security ────────────────────────────

test("voucher dengan eligibleUserIds whitelist → user di luar list HIDDEN", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-vip",
        code: "VIP",
        eligibleUserIds: ["user-alice", "user-bob"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx({ userId: "user-natsu" }), // bukan di list
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(
    items.length,
    0,
    "user di luar whitelist tidak boleh lihat voucher VIP",
  );
});

test("voucher dengan eligibleUserIds whitelist → user IN list TAMPIL", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-vip",
        code: "VIP",
        eligibleUserIds: ["user-alice", "user-natsu"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx({ userId: "user-natsu" }),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].code, "VIP");
  assert.equal(items[0].applicable, true);
});

// ─── getVoucherDisabledReason: voucher TAMPIL dengan reason ──────────

test("subtotal < minimumOrder → tampil di unavailable dengan reason", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-min",
        code: "MIN500K",
        minimumOrder: 500000,
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000, // < 500k
    now: NOW,
  });
  assert.equal(items.length, 1, "voucher tetap tampil walau belum eligible");
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("minimum belanja"),
    `expected reason about minimum belanja, got: ${items[0].disabledReason}`,
  );
});

test("voucher belum mulai (startsAt > now) → tampil dengan reason 'Voucher belum berlaku'", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-future",
        code: "UPCOMING",
        startsAt: new Date("2026-07-01T00:00:00Z"), // setelah NOW
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1, "voucher upcoming tetap tampil (preview)");
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.toLowerCase().includes("belum berlaku"),
    `expected 'belum berlaku', got: ${items[0].disabledReason}`,
  );
});

test("voucher NEW_MEMBER → user lama (sudah punya order) tampil dengan reason", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-newmember",
        code: "WELCOME",
        targetUser: "NEW_MEMBER",
        newMemberRequireNoSuccessfulOrder: true,
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx({ successfulOrderCount: 3 }), // user lama
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.toLowerCase().includes("akun baru"),
    `expected 'akun baru', got: ${items[0].disabledReason}`,
  );
});

test("voucher NEW_MEMBER → user baru (belum order) tampil applicable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-newmember",
        code: "WELCOME",
        targetUser: "NEW_MEMBER",
        newMemberRequireNoSuccessfulOrder: true,
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx({ successfulOrderCount: 0 }), // user baru
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

// ─── hasProductScope flag ────────────────────────────────────────────

test("voucher dengan eligibleProductIds → hasProductScope=true", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-scoped",
        code: "KUCING",
        eligibleProductIds: ["prod-kucing-001"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].hasProductScope, true);
});

test("voucher tanpa scope → hasProductScope=false", () => {
  const items = buildVoucherListItems({
    vouchers: [voucher({ id: "v-noscope", code: "ALL" })],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].hasProductScope, false);
});

// ─── Sort: applicable dulu, lalu disabled ────────────────────────────

test("sort: applicable dulu (best discount), lalu unavailable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-small",
        code: "SMALL",
        discountAmount: 5000,
      }),
      voucher({
        id: "v-min",
        code: "MIN",
        discountAmount: 50000,
        minimumOrder: 500000, // not applicable
      }),
      voucher({
        id: "v-big",
        code: "BIG",
        discountAmount: 20000,
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 3);
  // Applicable: BIG (20k) > SMALL (5k), lalu MIN (unavailable)
  assert.equal(items[0].code, "BIG");
  assert.equal(items[1].code, "SMALL");
  assert.equal(items[2].code, "MIN");
  assert.equal(items[0].applicable, true);
  assert.equal(items[1].applicable, true);
  assert.equal(items[2].applicable, false);
});

// ─── Free shipping voucher edge case ─────────────────────────────────

test("free shipping voucher → applicable=true bahkan kalau discount=0", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-fs",
        code: "GRATISONGKIR",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true, "free shipping always applicable");
  assert.equal(items[0].discount, 0, "discount=0 karena dihitung di shipping fee, bukan subtotal");
});

// ─── Kombinasi multi-kondisi ─────────────────────────────────────────

test("voucher publik admin yang lewat semua check → muncul dengan applicable=true", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-admin",
        code: "ADMIN10",
        userId: null, // publik
        discountPercent: 10,
        discountAmount: null, // override default 10000 → murni 10%
        minimumOrder: 50000,
        targetUser: "ALL_MEMBERS",
        eligibleUserIds: [],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx({ successfulOrderCount: 5 }),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
  assert.equal(items[0].discount, 10000); // 10% of 100k
  assert.equal(items[0].minimumOrder, 50000);
});

// ─── cartProducts scope gate (bug fix) ───────────────────────────────

test("voucher brand-scoped + cartProducts TIDAK ada brand yang cocok -> unavailable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-happydog",
        code: "HAPPYDOG15",
        eligibleBrandIds: ["brand-happydog"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "prod-1", categoryId: null, categorySlug: null, brandId: "brand-wollyplus" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("tidak berlaku"),
    `expected scope-mismatch reason, got: ${items[0].disabledReason}`,
  );
});

test("voucher brand-scoped + cartProducts ADA brand yang cocok -> applicable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-happydog",
        code: "HAPPYDOG15",
        eligibleBrandIds: ["brand-happydog"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "prod-1", categoryId: null, categorySlug: null, brandId: "brand-happydog" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

test("voucher brand-scoped + cartProducts TIDAK diberikan (undefined) -> permissive, tetap applicable (backward-compat)", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-happydog",
        code: "HAPPYDOG15",
        eligibleBrandIds: ["brand-happydog"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    // cartProducts sengaja tidak di-pass -- simulasi app lama yang belum
    // update, endpoint tidak boleh regress jadi mengunci voucher yang
    // sebelumnya applicable.
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

test("voucher tanpa scope apapun + cartProducts kosong -> tetap applicable (bukan false-positive)", () => {
  const items = buildVoucherListItems({
    vouchers: [voucher({ id: "v-all", code: "ALL10" })],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

// ─── brandName field ──────────────────────────────────────────────────

test("voucher dengan eligibleBrandIds + brandNamesById -> brandName terisi", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({ id: "v-b", code: "B15", eligibleBrandIds: ["brand-1"] }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    brandNamesById: new Map([["brand-1", "Wolly+"]]),
  });
  assert.equal(items[0].brandName, "Wolly+");
});

test("voucher tanpa eligibleBrandIds -> brandName null", () => {
  const items = buildVoucherListItems({
    vouchers: [voucher({ id: "v-noscope", code: "NOSCOPE" })],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items[0].brandName, null);
});

test("voucher SHIPPING brand-scoped + cartProducts tanpa brand cocok -> unavailable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-oks-hpi",
        code: "FREEOKSHPI",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
        eligibleBrandIds: ["brand-hpi"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "p1", categoryId: null, categorySlug: null, brandId: "brand-lain" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("tidak berlaku"),
    `expected scope-mismatch reason, got: ${items[0].disabledReason}`,
  );
});

test("voucher SHIPPING brand-scoped + cartProducts ADA brand cocok -> applicable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-oks-hpi",
        code: "FREEOKSHPI",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
        eligibleBrandIds: ["brand-hpi"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "p1", categoryId: null, categorySlug: null, brandId: "brand-hpi" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

test("voucher SHIPPING brand-scoped scope-mismatch + brandNamesById -> reason sebut nama brand", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-oks-hpi",
        code: "FREEOKSHPI",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
        eligibleBrandIds: ["brand-hpi"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "p1", categoryId: null, categorySlug: null, brandId: "brand-lain" },
    ],
    brandNamesById: new Map([["brand-hpi", "HPI"]]),
  });
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("HPI"),
    `expected brand name in reason, got: ${items[0].disabledReason}`,
  );
  assert.ok(
    items[0].disabledReason?.toLowerCase().includes("brand"),
    `expected 'brand' in reason, got: ${items[0].disabledReason}`,
  );
});
