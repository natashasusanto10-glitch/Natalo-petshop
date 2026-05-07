/**
 * GET /api/shipping/areas?keyword=jakarta+selatan
 *
 * Cari kota/kecamatan via Biteship Maps API. Untuk autocomplete kode pos.
 * Cache 24 jam.
 */
import { NextResponse } from "next/server";

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
    type RawArea = {
      id: string;
      name: string;
      country_name?: string;
      administrative_division_level_1_name?: string;
      administrative_division_level_2_name?: string;
      administrative_division_level_3_name?: string;
      administrative_division_level_4_name?: string;
      postal_code?: string | number;
    };

    const areas = Array.isArray(data.areas)
      ? data.areas.map((a: RawArea) => ({
          id: a.id,
          name: a.name,
          city: a.administrative_division_level_2_name ?? null,
          district: a.administrative_division_level_3_name ?? null,
          subdistrict: a.administrative_division_level_4_name ?? null,
          province: a.administrative_division_level_1_name ?? null,
          postal_code: a.postal_code ?? null,
        }))
      : [];

    return NextResponse.json({ areas });
  } catch (e) {
    return NextResponse.json(
      { areas: [], message: e instanceof Error ? e.message : "Error" },
      { status: 500 }
    );
  }
}
