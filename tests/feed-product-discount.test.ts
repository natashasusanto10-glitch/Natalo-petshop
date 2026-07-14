import assert from "node:assert/strict";
import test from "node:test";

import { resolveFeedProductDiscount } from "../lib/feed/queries";

const now = new Date("2026-07-14T00:00:00.000Z");
const future = new Date("2026-07-15T00:00:00.000Z");
const past = new Date("2026-07-13T00:00:00.000Z");

test("profile/feed pricing ignores an expired flash sale", () => {
  const result = resolveFeedProductDiscount(
    {
      price: 100_000,
      discountPrice: 80_000,
      flashSaleEndsAt: past,
      discountItems: [],
    },
    now,
  );

  assert.deepEqual(result, { discountPrice: null, discountSource: null });
});

test("profile/feed pricing returns the active store promotion", () => {
  const result = resolveFeedProductDiscount(
    {
      price: 100_000,
      discountPrice: null,
      flashSaleEndsAt: null,
      discountItems: [
        {
          variantId: null,
          discountedPrice: 72_000,
          discount: { endsAt: future },
        },
      ],
    },
    now,
  );

  assert.deepEqual(result, {
    discountPrice: 72_000,
    discountSource: "PROMO_TOKO",
  });
});

test("per-post promo price wins when it is the lowest active price", () => {
  const result = resolveFeedProductDiscount(
    {
      price: 100_000,
      discountPrice: 80_000,
      flashSaleEndsAt: future,
      discountItems: [],
    },
    now,
    65_000,
  );

  assert.deepEqual(result, {
    discountPrice: 65_000,
    discountSource: "PROMO_TOKO",
  });
});
