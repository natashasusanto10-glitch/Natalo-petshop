import { NextRequest, NextResponse } from "next/server";
import { mapGoogleAddress } from "@/lib/google-address";

function getGoogleMapsKey() {
  return process.env.GOOGLE_MAPS_KEY || process.env.GOOGLE_MAPS_API_KEY || "";
}

export async function POST(request: NextRequest) {
  const apiKey = getGoogleMapsKey();
  if (!apiKey) {
    return NextResponse.json({ error: "GOOGLE_MAPS_KEY belum dikonfigurasi." }, { status: 500 });
  }

  const body = await request.json().catch(() => ({}));
  const placeId = String(body.placeId ?? body.place_id ?? "").trim();
  if (!placeId) return NextResponse.json({ error: "placeId wajib diisi." }, { status: 400 });

  const params = new URLSearchParams({
    place_id: placeId,
    fields: "name,formatted_address,address_component,geometry",
    language: "id",
    key: apiKey,
  });

  const googleResponse = await fetch(
    `https://maps.googleapis.com/maps/api/place/details/json?${params.toString()}`,
    { cache: "no-store" }
  );
  const data = await googleResponse.json();
  const mapped = data?.result ? mapGoogleAddress(data.result) : null;

  if (mapped?.countryCode && mapped.countryCode !== "ID") {
    return NextResponse.json({ error: "Alamat harus berada di Indonesia." }, { status: 400 });
  }

  return NextResponse.json({ ...data, address: mapped }, { status: googleResponse.ok ? 200 : 502 });
}
