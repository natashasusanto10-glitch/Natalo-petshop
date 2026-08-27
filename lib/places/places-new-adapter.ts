/**
 * Adapter Places API (New) → bentuk respons Places API lama.
 *
 * KENAPA MENERJEMAHKAN, BUKAN MENGUBAH KONTRAK: klien Flutter yang sudah
 * terpasang di HP pelanggan membaca `predictions[]` dan `result` bergaya
 * lama. Kalau bentuk respons diubah, app versi lama langsung rusak dan
 * baru pulih setelah semua orang memperbarui — bisa berminggu-minggu.
 * Jadi rute tetap MENGELUARKAN bentuk lama; hanya jalur ke Google yang
 * pindah ke API baru.
 *
 * Project Google baru TIDAK BISA lagi memakai Places API lama. Dibuktikan
 * di produksi 2026-08-27 setelah kunci baru dipasang:
 *   "You're calling a legacy API, which is not enabled for your project."
 *
 * Perbedaan bentuk yang ditangani di sini:
 *   lama                          baru
 *   predictions[]                 suggestions[].placePrediction
 *   place_id                      placeId
 *   description                   text.text
 *   structured_formatting         structuredFormat
 *     .main_text                    .mainText.text
 *     .secondary_text               .secondaryText.text
 *   result.address_components     addressComponents
 *     .long_name / .short_name      .longText / .shortText
 *   result.geometry.location      location { latitude, longitude }
 *   result.formatted_address      formattedAddress
 */

export type LegacyPrediction = {
  place_id: string;
  description: string;
  structured_formatting: {
    main_text: string;
    secondary_text: string;
  };
};

export type LegacyAddressComponent = {
  long_name: string;
  short_name: string;
  types: string[];
};

export type LegacyPlaceResult = {
  /** WAJIB ada: klien Flutter membaca `result.place_id` (PlaceDetails
   *  .fromJson). API baru menamainya `id`. */
  place_id?: string;
  name?: string;
  formatted_address?: string;
  address_components?: LegacyAddressComponent[];
  geometry?: { location?: { lat: number; lng: number } };
};

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function textOf(node: unknown): string {
  if (!node || typeof node !== "object") return "";
  return str((node as { text?: unknown }).text);
}

/** `suggestions[]` (API baru) → `predictions[]` (bentuk lama). */
export function adaptAutocomplete(payload: unknown): LegacyPrediction[] {
  const suggestions = (payload as { suggestions?: unknown })?.suggestions;
  if (!Array.isArray(suggestions)) return [];

  const out: LegacyPrediction[] = [];
  for (const item of suggestions) {
    // Selain placePrediction, API baru juga bisa mengembalikan
    // queryPrediction (saran pencarian bebas, tanpa placeId). Itu tidak
    // bisa dipakai address picker — dibuang, jangan diloloskan dengan
    // placeId kosong.
    const p = (item as { placePrediction?: unknown })?.placePrediction;
    if (!p || typeof p !== "object") continue;
    const pred = p as Record<string, unknown>;
    const placeId = str(pred.placeId);
    if (!placeId) continue;

    const sf = pred.structuredFormat as Record<string, unknown> | undefined;
    out.push({
      place_id: placeId,
      description: textOf(pred.text),
      structured_formatting: {
        main_text: textOf(sf?.mainText),
        secondary_text: textOf(sf?.secondaryText),
      },
    });
  }
  return out;
}

/** Place detail (API baru) → `result` bergaya lama untuk mapGoogleAddress. */
export function adaptPlaceDetails(payload: unknown): LegacyPlaceResult | null {
  if (!payload || typeof payload !== "object") return null;
  const p = payload as Record<string, unknown>;

  const rawComponents = Array.isArray(p.addressComponents) ? p.addressComponents : [];
  const address_components: LegacyAddressComponent[] = rawComponents.map((c) => {
    const comp = (c ?? {}) as Record<string, unknown>;
    return {
      long_name: str(comp.longText),
      short_name: str(comp.shortText),
      types: Array.isArray(comp.types) ? comp.types.filter((t): t is string => typeof t === "string") : [],
    };
  });

  const loc = p.location as Record<string, unknown> | undefined;
  const lat = typeof loc?.latitude === "number" ? loc.latitude : null;
  const lng = typeof loc?.longitude === "number" ? loc.longitude : null;

  return {
    // API baru menamai place id sebagai `id`.
    place_id: str(p.id),
    // displayName API baru berbentuk { text, languageCode }, bukan string.
    name: textOf(p.displayName),
    formatted_address: str(p.formattedAddress),
    address_components,
    ...(lat !== null && lng !== null
      ? { geometry: { location: { lat, lng } } }
      : {}),
  };
}

/**
 * FieldMask WAJIB di Places API (New) — tanpa header ini Google menolak
 * dengan 400. Sengaja hanya meminta field yang benar-benar dipakai:
 * tiap field tambahan menaikkan tier penagihan.
 */
export const AUTOCOMPLETE_FIELD_MASK =
  "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat";

export const DETAILS_FIELD_MASK =
  "id,displayName,formattedAddress,addressComponents,location";
