/**
 * GET /api/shipping/areas?keyword=jakarta+selatan
 *
 * Cari area via Biteship Maps API. Dipakai untuk memilih destination_area_id
 * sehingga ongkir tidak bergantung pada free-text city/kode pos.
 * Cache 24 jam.
 */
import { NextResponse } from "next/server";
import { searchBiteshipAreas } from "@/lib/biteship-area";

export type ShippingArea = {
  area_id: string;
  label: string;
  province_name: string;
  city_name: string;
  district_name: string;
  postal_code: string;
};

export async function GET(request: Request) {
  const url = new URL(request.url);
  const keyword = (
    url.searchParams.get("keyword") ??
    url.searchParams.get("q") ??
    url.searchParams.get("input") ??
    ""
  ).trim();

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
    const areas = await searchBiteshipAreas(keyword);
    return NextResponse.json({ areas });
  } catch (e) {
    return NextResponse.json(
      { areas: [], message: e instanceof Error ? e.message : "Error" },
      { status: 500 }
    );
  }
}
