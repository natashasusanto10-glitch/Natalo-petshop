export {
  ORIGIN_AREA_NOT_CONFIGURED_CODE,
  SHIPPING_ORIGIN_UNAVAILABLE_DETAIL,
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
  toCustomerShippingErrorMessage,
} from "@/lib/shipping-messages";

type ShopOrigin = {
  origin_area_id?: string | null;
  originAreaId?: string | null;
};

type WarehouseOrigin = {
  area_id?: string | null;
  areaId?: string | null;
};

type OriginInput = {
  shop?: ShopOrigin | null;
  warehouse?: WarehouseOrigin | null;
};

function normalizeOriginValue(value: unknown) {
  const normalized = String(value ?? "").trim();
  return normalized.length > 0 ? normalized : null;
}

export function getOriginAreaId({ shop, warehouse }: OriginInput = {}) {
  return (
    normalizeOriginValue(process.env.SHOP_ORIGIN_AREA_ID) ||
    normalizeOriginValue(process.env.WAREHOUSE_AREA_ID) ||
    normalizeOriginValue(warehouse?.area_id) ||
    normalizeOriginValue(warehouse?.areaId) ||
    normalizeOriginValue(shop?.origin_area_id) ||
    normalizeOriginValue(shop?.originAreaId) ||
    null
  );
}

export function logMissingOriginArea({ shop, warehouse }: OriginInput = {}) {
  console.error("[Shipping Error] Origin area is missing", {
    shopOriginAreaId: shop?.origin_area_id ?? shop?.originAreaId ?? null,
    warehouseAreaId: warehouse?.area_id ?? warehouse?.areaId ?? null,
    envShopOriginAreaId: process.env.SHOP_ORIGIN_AREA_ID,
    envWarehouseAreaId: process.env.WAREHOUSE_AREA_ID,
  });
}
