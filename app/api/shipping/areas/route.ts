/**
 * GET /api/shipping/areas?keyword=jakarta+selatan
 *
 * Cari area via Biteship Maps API. Dipakai untuk memilih destination_area_id
 * sehingga ongkir tidak bergantung pada free-text city/kode pos.
 * Cache 24 jam.
 */
import { NextResponse } from "next/server";

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
  country_name?: string;
  administrative_division_level_1_name?: string;
  administrative_division_level_2_name?: string;
  administrative_division_level_3_name?: string;
  administrative_division_level_4_name?: string;
  postal_code?: string | number;
};

export async function GET(request: Request) {
  const url = new URL(request.url);
  const keyword = (url.searchParams.get("keyword") ?? "").trim();

  if (keyword.length < 3) {
    return NextResponse.json({ areas: [] });
  }

  const apiKey = process.env.BITESHIP_API_KEY;
  if (!apiKey) {
    return NextResponse.json({
      areas: [],
      message: "BITESHIP_API_KEY belum diisi.",
    });
  }

  try {
    const res = await fetch(
      `https://api.biteship.com/v1/maps/areas?countries=ID&input=${encodeURIComponent(keyword)}&type=single`,
      {
        headers: { Authorization: apiKey },
        next: { revalidate: 86400 }, // cache 24 jam
      }
    );

    if (!res.ok) {
      return NextResponse.json(
        { areas: [], message: "Gagal kontak Biteship." },
        { status: 500 }
      );
    }

    const data = await res.json();
    const areas = Array.isArray(data.areas)
      ? data.areas
          .map(normalizeArea)
          .filter((area: ShippingArea | null): area is ShippingArea => Boolean(area))
      : [];

    return NextResponse.json({ areas });
  } catch (e) {
    return NextResponse.json(
      { areas: [], message: e instanceof Error ? e.message : "Error" },
      { status: 500 }
    );
  }
}

function normalizeArea(area: RawBiteshipArea): ShippingArea | null {
  const areaId = String(area.area_id ?? area.id ?? "").trim();
  const province = String(area.administrative_division_level_1_name ?? "").trim();
  const city = String(area.administrative_division_level_2_name ?? "").trim();
  const district = String(
    area.administrative_division_level_3_name ??
      area.administrative_division_level_4_name ??
      area.name ??
      "",
  ).trim();
  const postalCode = String(area.postal_code ?? "").trim();

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
