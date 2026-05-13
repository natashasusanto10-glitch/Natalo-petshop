export const SELF_PICKUP_METHOD = "SELF_PICKUP" as const;
export const DELIVERY_METHOD = "DELIVERY" as const;

export const SELF_PICKUP_STORE = {
  name: "Natalo Petshop / Sinar Petstore",
  addressLine: "Jln MT. Haryono No 103 B C D",
  area: "Pusat Pasar, Medan Kota",
  address: "Jln MT. Haryono No 103 B C D, Pusat Pasar, Medan Kota",
  hours: "09.00 - 17.00 WIB",
  latitude: null as number | null,
  longitude: null as number | null,
};

export function buildSelfPickupMapsUrl() {
  if (
    SELF_PICKUP_STORE.latitude !== null &&
    SELF_PICKUP_STORE.longitude !== null
  ) {
    return `https://www.google.com/maps/search/?api=1&query=${SELF_PICKUP_STORE.latitude},${SELF_PICKUP_STORE.longitude}`;
  }

  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
    SELF_PICKUP_STORE.address
  )}`;
}

export function isSelfPickupMethod(value?: string | null) {
  return value === SELF_PICKUP_METHOD;
}

export function createPickupCode() {
  return `NTL-${Math.floor(1000 + Math.random() * 9000)}`;
}
