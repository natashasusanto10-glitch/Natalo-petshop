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
  const lat = Number(body.lat ?? body.latitude);
  const lng = Number(body.lng ?? body.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return NextResponse.json({ error: "Koordinat tidak valid." }, { status: 400 });
  }

  const params = new URLSearchParams({
    latlng: `${lat},${lng}`,
    language: "id",
    result_type: "street_address|route|premise|subpremise|point_of_interest",
    key: apiKey,
  });

  const googleResponse = await fetch(
    `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`,
    { cache: "no-store" }
  );
  const data = await googleResponse.json();
  const result = data?.results?.[0] ?? null;
  const mapped = result ? mapGoogleAddress(result) : null;

  if (mapped?.countryCode && mapped.countryCode !== "ID") {
    return NextResponse.json({ error: "Alamat harus berada di Indonesia." }, { status: 400 });
  }

  return NextResponse.json({ ...data, address: mapped }, { status: googleResponse.ok ? 200 : 502 });
}
