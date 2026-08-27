import { NextRequest, NextResponse } from "next/server";
import { mapGoogleAddress } from "@/lib/google-address";
import { getGoogleMapsServerKey } from "@/lib/google-maps-key";
import { checkLimit, getClientIp, getMapsLimiter } from "@/lib/rate-limit";
import {
  DETAILS_FIELD_MASK,
  adaptPlaceDetails,
} from "@/lib/places/places-new-adapter";

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

  // Places API (New): GET /v1/places/{placeId}. placeId di-encode karena
  // datang dari klien — walau format Google aman, jangan percaya masukan.
  let googleResponse: Response;
  try {
    googleResponse = await fetch(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?languageCode=id`,
      {
        headers: {
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask": DETAILS_FIELD_MASK,
        },
        cache: "no-store",
      },
    );
  } catch (e) {
    console.error("[places/details] gagal menghubungi Google", e);
    return NextResponse.json(
      { error: "Layanan pencarian alamat tidak dapat dihubungi." },
      { status: 502 },
    );
  }

  const data = await googleResponse.json().catch(() => null);

  if (!googleResponse.ok) {
    const detail = (data as { error?: { status?: string; message?: string } } | null)?.error;
    console.error(
      `[places/details] Google menolak: HTTP ${googleResponse.status} ${detail?.status ?? ""} — ${String(detail?.message ?? "").slice(0, 200)}`,
    );
    return NextResponse.json(
      { error: "Detail alamat tidak dapat diambil. Coba pilih alamat lain." },
      { status: googleResponse.status === 404 ? 404 : 503 },
    );
  }

  // Terjemahkan ke bentuk lama supaya mapGoogleAddress (dan app versi
  // lama) tidak perlu berubah sama sekali.
  const result = adaptPlaceDetails(data);
  const mapped = result ? mapGoogleAddress(result) : null;

  if (mapped?.countryCode && mapped.countryCode !== "ID") {
    return NextResponse.json({ error: "Alamat harus berada di Indonesia." }, { status: 400 });
  }

  return NextResponse.json({ result, address: mapped, status: "OK" });
}
