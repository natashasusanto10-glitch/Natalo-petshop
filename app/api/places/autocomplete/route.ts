import { NextRequest, NextResponse } from "next/server";
import { getGoogleMapsServerKey } from "@/lib/google-maps-key";
import { checkLimit, getClientIp, getMapsLimiter } from "@/lib/rate-limit";
import {
  AUTOCOMPLETE_FIELD_MASK,
  adaptAutocomplete,
} from "@/lib/places/places-new-adapter";

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
  const input = String(body.input ?? body.query ?? "").trim();
  if (input.length < 2) {
    return NextResponse.json({ predictions: [], status: "ZERO_RESULTS" });
  }

  // Places API (New): POST + JSON body ke host places.googleapis.com,
  // kunci lewat header X-Goog-Api-Key (BUKAN query param `key`), dan
  // X-Goog-FieldMask WAJIB — tanpa itu Google menolak dengan 400.
  const payload: Record<string, unknown> = {
    input,
    includedRegionCodes: ["id"],
    languageCode: "id",
  };

  // Bias lokasi: bentuk lama `location=lat,lng` + `radius` menjadi
  // locationBias.circle. Radius Google dibatasi 50 km.
  const lat = Number(body.lat);
  const lng = Number(body.lng);
  const [locLat, locLng] = String(body.location ?? "")
    .split(",")
    .map((v) => Number(v));
  const biasLat = Number.isFinite(lat) ? lat : locLat;
  const biasLng = Number.isFinite(lng) ? lng : locLng;
  if (Number.isFinite(biasLat) && Number.isFinite(biasLng)) {
    payload.locationBias = {
      circle: {
        center: { latitude: biasLat, longitude: biasLng },
        radius: Math.min(Number(body.radius) || 2000, 50000),
      },
    };
  }

  let googleResponse: Response;
  try {
    googleResponse = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": AUTOCOMPLETE_FIELD_MASK,
      },
      body: JSON.stringify(payload),
      cache: "no-store",
    });
  } catch (e) {
    console.error("[places/autocomplete] gagal menghubungi Google", e);
    return NextResponse.json(
      { error: "Layanan pencarian alamat tidak dapat dihubungi.", predictions: [] },
      { status: 502 },
    );
  }

  const data = await googleResponse.json().catch(() => null);

  // API baru memakai HTTP status sungguhan (beda dari API lama yang selalu
  // 200 dengan field `status`). Pesan MENTAH Google tidak diteruskan ke
  // pengguna — bisa memuat nama project/kunci; cukup dicatat di log.
  if (!googleResponse.ok) {
    const detail = (data as { error?: { status?: string; message?: string } } | null)?.error;
    console.error(
      `[places/autocomplete] Google menolak: HTTP ${googleResponse.status} ${detail?.status ?? ""} — ${String(detail?.message ?? "").slice(0, 200)}`,
    );
    return NextResponse.json(
      {
        error: "Layanan pencarian alamat sedang tidak tersedia. Silakan isi alamat secara manual.",
        predictions: [],
      },
      { status: googleResponse.status === 400 ? 502 : 503 },
    );
  }

  // Bentuk keluaran SENGAJA tetap gaya lama (`predictions[]`) — app yang
  // sudah terpasang di HP pelanggan membacanya. Mengubah kontrak di sini
  // akan merusak semua versi lama sampai semua orang memperbarui.
  const predictions = adaptAutocomplete(data);
  return NextResponse.json({
    predictions,
    status: predictions.length ? "OK" : "ZERO_RESULTS",
  });
}
