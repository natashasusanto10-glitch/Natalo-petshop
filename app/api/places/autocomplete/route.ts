import { NextRequest, NextResponse } from "next/server";
import { getGoogleMapsServerKey } from "@/lib/google-maps-key";

export async function POST(request: NextRequest) {
  const apiKey = getGoogleMapsServerKey();
  if (!apiKey) {
    return NextResponse.json(
      { error: "GOOGLE_MAPS_KEY atau NEXT_PUBLIC_GOOGLE_MAPS_KEY belum dikonfigurasi." },
      { status: 500 },
    );
  }

  const body = await request.json().catch(() => ({}));
  const input = String(body.input ?? "").trim();
  if (input.length < 2) {
    return NextResponse.json({ predictions: [], status: "ZERO_RESULTS" });
  }

  const params = new URLSearchParams({
    input,
    radius: String(body.radius || 2000),
    components: "country:id",
    language: "id",
    key: apiKey,
  });

  if (body.location) params.set("location", String(body.location));

  const googleResponse = await fetch(
    `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params.toString()}`,
    { cache: "no-store" }
  );
  const data = await googleResponse.json();

  return NextResponse.json(data, { status: googleResponse.ok ? 200 : 502 });
}
