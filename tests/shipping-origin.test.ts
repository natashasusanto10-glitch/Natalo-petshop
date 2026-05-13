import assert from "node:assert/strict";
import test from "node:test";
import {
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
  toCustomerShippingErrorMessage,
} from "@/lib/shipping-messages";
import {
  getOriginAreaId,
} from "@/lib/shipping-origin";

function withOriginEnv(
  env: { SHOP_ORIGIN_AREA_ID?: string; WAREHOUSE_AREA_ID?: string },
  callback: () => void,
) {
  const previousShopOrigin = process.env.SHOP_ORIGIN_AREA_ID;
  const previousWarehouse = process.env.WAREHOUSE_AREA_ID;

  process.env.SHOP_ORIGIN_AREA_ID = env.SHOP_ORIGIN_AREA_ID ?? "";
  process.env.WAREHOUSE_AREA_ID = env.WAREHOUSE_AREA_ID ?? "";

  try {
    callback();
  } finally {
    if (previousShopOrigin === undefined) {
      delete process.env.SHOP_ORIGIN_AREA_ID;
    } else {
      process.env.SHOP_ORIGIN_AREA_ID = previousShopOrigin;
    }

    if (previousWarehouse === undefined) {
      delete process.env.WAREHOUSE_AREA_ID;
    } else {
      process.env.WAREHOUSE_AREA_ID = previousWarehouse;
    }
  }
}

test("origin area prefers shop env, then warehouse env, then stored warehouse and shop values", () => {
  withOriginEnv({ SHOP_ORIGIN_AREA_ID: "shop-env", WAREHOUSE_AREA_ID: "warehouse-env" }, () => {
    assert.equal(getOriginAreaId({ warehouse: { area_id: "warehouse-db" }, shop: { origin_area_id: "shop-db" } }), "shop-env");
  });

  withOriginEnv({ SHOP_ORIGIN_AREA_ID: "", WAREHOUSE_AREA_ID: "warehouse-env" }, () => {
    assert.equal(getOriginAreaId({ warehouse: { area_id: "warehouse-db" }, shop: { origin_area_id: "shop-db" } }), "warehouse-env");
  });

  withOriginEnv({ SHOP_ORIGIN_AREA_ID: "", WAREHOUSE_AREA_ID: "" }, () => {
    assert.equal(getOriginAreaId({ warehouse: { area_id: "warehouse-db" }, shop: { origin_area_id: "shop-db" } }), "warehouse-db");
    assert.equal(getOriginAreaId({ shop: { origin_area_id: "shop-db" } }), "shop-db");
  });
});

test("technical origin config errors are converted to customer friendly text", () => {
  assert.equal(
    toCustomerShippingErrorMessage("Isi SHOP_ORIGIN_AREA_ID atau WAREHOUSE_AREA_ID."),
    SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
  );
});
