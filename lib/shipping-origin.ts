export {
  ORIGIN_AREA_NOT_CONFIGURED_CODE,
  SHIPPING_ORIGIN_UNAVAILABLE_DETAIL,
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
  toCustomerShippingErrorMessage,
} from "@/lib/shipping-messages";
import { searchBiteshipAreas } from "@/lib/biteship-area";

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

let resolvedOriginAreaId: string | null | undefined;

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

function uniqueCandidates(values: Array<string | null>) {
  return values
    .map((value) => normalizeOriginValue(value))
    .filter((value): value is string => Boolean(value))
    .filter((value, index, list) => value.length >= 3 && list.indexOf(value) === index);
}

export async function resolveOriginAreaId(input: OriginInput = {}) {
  const configured = getOriginAreaId(input);
  if (configured) return configured;

  if (resolvedOriginAreaId !== undefined) return resolvedOriginAreaId;

  const address = normalizeOriginValue(process.env.SHOP_ORIGIN_ADDRESS);
  const district = normalizeOriginValue(process.env.SHOP_ORIGIN_DISTRICT);
  const city = normalizeOriginValue(process.env.SHOP_ORIGIN_CITY);
  const province = normalizeOriginValue(process.env.SHOP_ORIGIN_PROVINCE);
  const postalCode = normalizeOriginValue(process.env.SHOP_ORIGIN_POSTAL_CODE);
  const publicAddress = normalizeOriginValue(process.env.NEXT_PUBLIC_STORE_ADDRESS);

  const candidates = uniqueCandidates([
    [district, city, postalCode].filter(Boolean).join(" "),
    [district, city].filter(Boolean).join(" "),
    [city, postalCode].filter(Boolean).join(" "),
    [address, postalCode].filter(Boolean).join(" "),
    [publicAddress, postalCode].filter(Boolean).join(" "),
    postalCode,
    address,
    publicAddress,
  ]);

  for (const keyword of candidates) {
    const areas = await searchBiteshipAreas(keyword);
    const match =
      areas.find(
        (area) =>
          (!postalCode || area.postal_code === postalCode) &&
          (!city || area.city_name.toLowerCase().includes(city.toLowerCase())) &&
          (!province || area.province_name.toLowerCase().includes(province.toLowerCase())),
      ) ??
      (postalCode ? areas.find((area) => area.postal_code === postalCode) : null) ??
      areas[0] ??
      null;

    if (match?.area_id) {
      resolvedOriginAreaId = match.area_id;
      return resolvedOriginAreaId;
    }
  }

  resolvedOriginAreaId = null;
  return null;
}

export function logMissingOriginArea({ shop, warehouse }: OriginInput = {}) {
  console.error("[Shipping Error] Origin area is missing", {
    shopOriginAreaId: shop?.origin_area_id ?? shop?.originAreaId ?? null,
    warehouseAreaId: warehouse?.area_id ?? warehouse?.areaId ?? null,
    envShopOriginAreaId: process.env.SHOP_ORIGIN_AREA_ID,
    envWarehouseAreaId: process.env.WAREHOUSE_AREA_ID,
  });
}
