import { NextRequest, NextResponse } from "next/server";
import { mapGoogleAddress } from "@/lib/google-address";
import { getGoogleMapsServerKey } from "@/lib/google-maps-key";
import { checkLimit, getClientIp, getMapsLimiter } from "@/lib/rate-limit";
import { googleStatusLogLine, interpretGoogleStatus } from "@/lib/places/google-status";

export async function POST(request: NextRequest) {
  const ip = getClientIp(request.headers);
  const gate = await checkLimit(getMapsLimiter(), `places-details:${ip}`);
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

  // Google membalas HTTP 200 walau menolak — lihat lib/places/google-status.ts.
  const verdict = interpretGoogleStatus(data?.status);
  if (!verdict.ok) {
    console.error(googleStatusLogLine("details", data?.status, data?.error_message));
    return NextResponse.json({ error: verdict.error }, { status: verdict.httpStatus });
  }

  const mapped = data?.result ? mapGoogleAddress(data.result) : null;

  if (mapped?.countryCode && mapped.countryCode !== "ID") {
    return NextResponse.json({ error: "Alamat harus berada di Indonesia." }, { status: 400 });
  }

  return NextResponse.json({ ...data, address: mapped });
}
