import { DEFAULT_SHOP_ORIGIN } from "@/lib/shipping-origin";

export const SELF_PICKUP_METHOD = "SELF_PICKUP" as const;
export const DELIVERY_METHOD = "DELIVERY" as const;
export const SELF_PICKUP_MAPS_URL = "https://share.google/NAfEiYygBy9zIMXoU";

export const SELF_PICKUP_STORE = {
  name: "Natalo Petshop / Sinar Petstore",
  addressLine: "JLN MT Haryono No 103 B C D",
  area: "Pusat Pasar, Medan Kota",
  address: "JLN MT Haryono No 103 B C D, Pusat Pasar, Medan Kota",
  hours: "09.00 - 17.00 WIB",
  latitude: DEFAULT_SHOP_ORIGIN.latitude as number | null,
  longitude: DEFAULT_SHOP_ORIGIN.longitude as number | null,
};

export function buildSelfPickupMapsUrl() {
  return SELF_PICKUP_MAPS_URL;
}

export function isSelfPickupMethod(value?: string | null) {
  return value === SELF_PICKUP_METHOD;
}

export function createPickupCode() {
  return `NTL-${Math.floor(1000 + Math.random() * 9000)}`;
}
