import { NextRequest, NextResponse } from "next/server";
import { mapGoogleAddress } from "@/lib/google-address";
import { getGoogleMapsServerKey } from "@/lib/google-maps-key";
import { checkLimit, getClientIp, getMapsLimiter } from "@/lib/rate-limit";

export async function POST(request: NextRequest) {
  const ip = getClientIp(request.headers);
  const gate = await checkLimit(getMapsLimiter(), `places-reverse:${ip}`);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Terlalu banyak permintaan. Tunggu sebentar." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } },
    );
  }

  const apiKey = getGoogleMapsServerKey();
  if (!apiKey) {
    return NextResponse.json(
      { error: "GOOGLE_MAPS_KEY atau NEXT_PUBLIC_GOOGLE_MAPS_KEY belum dikonfigurasi." },
      { status: 500 },
    );
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
