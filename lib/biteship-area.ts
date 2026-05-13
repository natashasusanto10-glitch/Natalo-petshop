export type ShippingArea = {
  area_id: string;
  label: string;
  province_name: string;
  city_name: string;
  district_name: string;
  postal_code: string;
};

type RawBiteshipArea = {
  id?: string;
  area_id?: string;
  name?: string;
  administrative_division_level_1_name?: string;
  administrative_division_level_2_name?: string;
  administrative_division_level_3_name?: string;
  administrative_division_level_4_name?: string;
  postal_code?: string | number;
};

type AddressAreaInput = {
  address?: string | null;
  areaId?: string | null;
  city?: string | null;
  cityName?: string | null;
  districtName?: string | null;
  postalCode?: string | null;
  provinceName?: string | null;
};

function normalizeText(value: unknown) {
  return String(value ?? "")
    .toLowerCase()
    .replace(/\b(kota|kabupaten|kab|kec|kecamatan)\b/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function includesNormalized(value: unknown, needle: unknown) {
  const text = normalizeText(value);
  const query = normalizeText(needle);
  return Boolean(text && query && (text.includes(query) || query.includes(text)));
}

export function normalizeBiteshipArea(area: RawBiteshipArea): ShippingArea | null {
  const areaId = String(area?.area_id ?? area?.id ?? "").trim();
  const province = String(area?.administrative_division_level_1_name ?? "").trim();
  const city = String(area?.administrative_division_level_2_name ?? "").trim();
  const district = String(
    area?.administrative_division_level_3_name ??
      area?.administrative_division_level_4_name ??
      area?.name ??
      "",
  ).trim();
  const postalCode = String(area?.postal_code ?? "").trim();

  if (!areaId || !postalCode || !city || !province) return null;

  return {
    area_id: areaId,
    label: `${district || city}, ${city}, ${province}. ${postalCode}`,
    province_name: province,
    city_name: city,
    district_name: district || city,
    postal_code: postalCode,
  };
}

export async function searchBiteshipAreas(keyword: string): Promise<ShippingArea[]> {
  const apiKey = process.env.BITESHIP_API_KEY;
  const input = String(keyword ?? "").trim();
  if (!apiKey || input.length < 3) return [];

  const response = await fetch(
    `https://api.biteship.com/v1/maps/areas?countries=ID&input=${encodeURIComponent(input)}&type=single`,
    {
      headers: { Authorization: apiKey },
      next: { revalidate: 86400 },
    },
  );

  if (!response.ok) return [];

  const data = (await response.json()) as { areas?: RawBiteshipArea[] };
  return Array.isArray(data.areas)
    ? data.areas.map(normalizeBiteshipArea).filter((area): area is ShippingArea => Boolean(area))
    : [];
}

export async function findBiteshipAreaForAddress(
  address: AddressAreaInput,
): Promise<ShippingArea | null> {
  if (address.areaId) return null;

  const district = address.districtName;
  const city = address.cityName || address.city;
  const province = address.provinceName;
  const postalCode = address.postalCode;
  const candidates = [
    [district, city, postalCode].filter(Boolean).join(" "),
    [district, city].filter(Boolean).join(" "),
    [city, postalCode].filter(Boolean).join(" "),
    [address.address, district, city].filter(Boolean).join(" "),
  ].filter((value, index, list) => value.length >= 3 && list.indexOf(value) === index);

  for (const keyword of candidates) {
    const areas = await searchBiteshipAreas(keyword);
    const exact = areas.find(
      (area) =>
        (!postalCode || area.postal_code === postalCode) &&
        (!district || includesNormalized(area.district_name, district)) &&
        (!city || includesNormalized(area.city_name, city)) &&
        (!province || includesNormalized(area.province_name, province)),
    );
    if (exact) return exact;

    const samePostal = postalCode ? areas.find((area) => area.postal_code === postalCode) : null;
    if (samePostal) return samePostal;

    const sameDistrict = areas.find(
      (area) =>
        (!district || includesNormalized(area.district_name, district)) &&
        (!city || includesNormalized(area.city_name, city)),
    );
    if (sameDistrict) return sameDistrict;
  }

  return null;
}
