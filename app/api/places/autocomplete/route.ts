import { NextRequest, NextResponse } from "next/server";
import { getGoogleMapsServerKey } from "@/lib/google-maps-key";
import { checkLimit, getClientIp, getMapsLimiter } from "@/lib/rate-limit";

export async function POST(request: NextRequest) {
  // Tanpa rate limit endpoint ini = direct passthrough billing ke Google
  // Maps. Attacker bisa loop POST tanpa auth → cost-DoS. 30 calls/menit
  // cukup untuk UX autocomplete normal (user ketik ~10 char dlm 10 detik).
  const ip = getClientIp(request.headers);
  const gate = await checkLimit(getMapsLimiter(), `places-autocomplete:${ip}`);
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
