type GoogleAddressComponent = {
  long_name: string;
  short_name: string;
  types: string[];
};

type GoogleGeocodeResult = {
  formatted_address?: string;
  address_components?: GoogleAddressComponent[];
  geometry?: {
    location?: {
      lat: number;
      lng: number;
    };
  };
  name?: string;
};

function component(components: GoogleAddressComponent[] | undefined, type: string) {
  return components?.find((item) => item.types.includes(type))?.long_name ?? "";
}

export function mapGoogleAddress(result: GoogleGeocodeResult) {
  const components = result.address_components ?? [];
  const countryCode =
    components.find((item) => item.types.includes("country"))?.short_name?.toUpperCase() ?? "";
  const route = component(components, "route");
  const streetNumber = component(components, "street_number");
  const street = [route, streetNumber].filter(Boolean).join(" ") ||
    result.name ||
    result.formatted_address?.split(",")[0] ||
    "";
  const district =
    component(components, "administrative_area_level_3") ||
    component(components, "sublocality_level_1") ||
    component(components, "administrative_area_level_4");
  const city =
    component(components, "administrative_area_level_2") ||
    component(components, "locality") ||
    component(components, "administrative_area_level_1");

  return {
    jalan: street,
    provinsi: component(components, "administrative_area_level_1"),
    kota: city,
    kecamatan: district,
    kodePos: component(components, "postal_code"),
    lat: result.geometry?.location?.lat ?? null,
    lng: result.geometry?.location?.lng ?? null,
    formattedAddress: result.formatted_address ?? "",
    countryCode,
  };
}
