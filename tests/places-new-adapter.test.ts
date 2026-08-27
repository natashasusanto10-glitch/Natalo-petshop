import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  adaptAutocomplete,
  adaptPlaceDetails,
  AUTOCOMPLETE_FIELD_MASK,
  DETAILS_FIELD_MASK,
} from "../lib/places/places-new-adapter";
import { mapGoogleAddress } from "../lib/google-address";

describe("adapter Places API (New) -> bentuk lama", () => {
  it("suggestions[] jadi predictions[] gaya lama", () => {
    // Bentuk respons Places API (New) sesuai FieldMask yang kita minta.
    const baru = {
      suggestions: [
        {
          placePrediction: {
            placeId: "ChIJ_abc123",
            text: { text: "Sinar Baru Aquarium, Jl. Gatot Subroto, Medan" },
            structuredFormat: {
              mainText: { text: "Sinar Baru Aquarium" },
              secondaryText: { text: "Jl. Gatot Subroto, Medan" },
            },
          },
        },
      ],
    };

    const hasil = adaptAutocomplete(baru);
    assert.equal(hasil.length, 1);
    // Nama field WAJIB gaya lama — app yang sudah terpasang membacanya.
    assert.equal(hasil[0].place_id, "ChIJ_abc123");
    assert.match(hasil[0].description, /Sinar Baru Aquarium/);
    assert.equal(hasil[0].structured_formatting.main_text, "Sinar Baru Aquarium");
    assert.equal(hasil[0].structured_formatting.secondary_text, "Jl. Gatot Subroto, Medan");
  });

  it("queryPrediction DIBUANG — tidak punya placeId, tak bisa dipakai", () => {
    // API baru bisa mengembalikan saran pencarian bebas. Kalau diloloskan
    // dengan placeId kosong, pengguna menekannya lalu tidak terjadi apa-apa.
    const campuran = {
      suggestions: [
        { queryPrediction: { text: { text: "aquarium di medan" } } },
        {
          placePrediction: {
            placeId: "ChIJ_ok",
            text: { text: "Toko Aquarium" },
            structuredFormat: { mainText: { text: "Toko Aquarium" } },
          },
        },
      ],
    };
    const hasil = adaptAutocomplete(campuran);
    assert.equal(hasil.length, 1);
    assert.equal(hasil[0].place_id, "ChIJ_ok");
  });

  it("tahan respons kosong / bentuk tak terduga", () => {
    for (const buruk of [null, undefined, {}, { suggestions: null }, { suggestions: "x" }]) {
      assert.deepEqual(adaptAutocomplete(buruk), []);
    }
    // placePrediction tanpa placeId juga dibuang.
    assert.deepEqual(
      adaptAutocomplete({ suggestions: [{ placePrediction: { text: { text: "x" } } }] }),
      [],
    );
  });

  it("detail place jadi result lama DAN lolos mapGoogleAddress", () => {
    // Ini asersi terpenting: hasil adaptasi harus bisa langsung dipakai
    // mapGoogleAddress yang TIDAK diubah sama sekali.
    const baru = {
      id: "ChIJ_abc123",
      displayName: { text: "Sinar Baru Aquarium", languageCode: "id" },
      formattedAddress: "Jl. Gatot Subroto No.10, Medan, Sumatera Utara 20212, Indonesia",
      location: { latitude: 3.5952, longitude: 98.6722 },
      addressComponents: [
        { longText: "10", shortText: "10", types: ["street_number"] },
        { longText: "Jalan Gatot Subroto", shortText: "Jl. Gatot Subroto", types: ["route"] },
        { longText: "Medan Petisah", shortText: "Medan Petisah", types: ["administrative_area_level_3"] },
        { longText: "Kota Medan", shortText: "Medan", types: ["administrative_area_level_2"] },
        { longText: "Sumatera Utara", shortText: "SU", types: ["administrative_area_level_1"] },
        { longText: "20212", shortText: "20212", types: ["postal_code"] },
        { longText: "Indonesia", shortText: "ID", types: ["country"] },
      ],
    };

    const result = adaptPlaceDetails(baru);
    assert.ok(result);
    // place_id WAJIB diteruskan — Flutter membaca result.place_id.
    assert.equal(result!.place_id, "ChIJ_abc123");
    assert.equal(result!.name, "Sinar Baru Aquarium");
    assert.equal(result!.geometry?.location?.lat, 3.5952);
    assert.equal(result!.geometry?.location?.lng, 98.6722);

    const alamat = mapGoogleAddress(result!);
    assert.equal(alamat.jalan, "Jalan Gatot Subroto 10");
    assert.equal(alamat.kota, "Kota Medan");
    assert.equal(alamat.provinsi, "Sumatera Utara");
    assert.equal(alamat.kecamatan, "Medan Petisah");
    assert.equal(alamat.kodePos, "20212");
    // countryCode dipakai gerbang "harus di Indonesia" di rute details.
    assert.equal(alamat.countryCode, "ID");
    assert.equal(alamat.lat, 3.5952);
  });

  it("detail tanpa koordinat tidak memalsukan geometry", () => {
    const r = adaptPlaceDetails({ formattedAddress: "x", addressComponents: [] });
    assert.ok(r);
    assert.equal(r!.geometry, undefined);
    assert.equal(mapGoogleAddress(r!).lat, null);
  });

  it("detail bentuk buruk jadi null, bukan objek setengah jadi", () => {
    for (const buruk of [null, undefined, "teks", 42]) {
      assert.equal(adaptPlaceDetails(buruk), null);
    }
  });

  it("FieldMask hanya meminta field yang dipakai — tiap field menaikkan tagihan", () => {
    // Regresi biaya: menambah field ke mask menaikkan tier penagihan
    // Google. Kalau ada yang menambahkannya, test ini yang menahan.
    assert.equal(
      AUTOCOMPLETE_FIELD_MASK,
      "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat",
    );
    assert.equal(DETAILS_FIELD_MASK, "id,displayName,formattedAddress,addressComponents,location");
    // FieldMask WAJIB ada — tanpa header ini Google menolak dengan 400.
    assert.ok(AUTOCOMPLETE_FIELD_MASK.length > 0);
    assert.ok(DETAILS_FIELD_MASK.length > 0);
  });
});
