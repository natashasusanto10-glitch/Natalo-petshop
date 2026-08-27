import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  googleStatusLogLine,
  interpretGoogleStatus,
} from "../lib/places/google-status";

describe("penerjemah status Google Places", () => {
  it("REQUEST_DENIED jadi 503 bukan 200 — kasus produksi 2026-08-27", () => {
    // Ini respons ASLI dari produksi saat billing Google nonaktif: Google
    // membalas HTTP 200 dengan predictions kosong. Rute lama meneruskannya
    // apa adanya, jadi app menampilkan "tidak ada hasil" — tak bisa
    // dibedakan dari pencarian nihil, dan nol jejak di log.
    const v = interpretGoogleStatus("REQUEST_DENIED");
    assert.equal(v.ok, false);
    assert.equal(v.httpStatus, 503);
    assert.equal(v.isConfigError, true);
    assert.match(String(v.error), /tidak tersedia/);
  });

  it("ZERO_RESULTS TETAP sukses — pencarian nihil bukan kegagalan", () => {
    const v = interpretGoogleStatus("ZERO_RESULTS");
    assert.equal(v.ok, true);
    assert.equal(v.httpStatus, 200);
    assert.equal(v.error, null);
  });

  it("OK sukses", () => {
    assert.equal(interpretGoogleStatus("OK").ok, true);
  });

  it("kuota habis jadi 503 dengan pesan 'coba lagi'", () => {
    const v = interpretGoogleStatus("OVER_QUERY_LIMIT");
    assert.equal(v.httpStatus, 503);
    assert.match(String(v.error), /Coba lagi/i);
  });

  it("INVALID_REQUEST jadi 400 dan ditandai salah konfigurasi kita", () => {
    const v = interpretGoogleStatus("INVALID_REQUEST");
    assert.equal(v.httpStatus, 400);
    assert.equal(v.isConfigError, true);
  });

  it("NOT_FOUND bukan salah konfigurasi", () => {
    const v = interpretGoogleStatus("NOT_FOUND");
    assert.equal(v.httpStatus, 404);
    assert.equal(v.isConfigError, false);
  });

  it("status tak dikenal / body tanpa status jadi 502, tidak dianggap sukses", () => {
    for (const bad of ["SESUATU_YANG_BARU", undefined, null, 123, {}]) {
      const v = interpretGoogleStatus(bad);
      assert.equal(v.ok, false, `harus gagal untuk ${JSON.stringify(bad)}`);
      assert.equal(v.httpStatus, 502);
    }
  });

  it("pesan mentah Google TIDAK PERNAH bocor ke pengguna", () => {
    // Pesan Google memuat URL project dan petunjuk konfigurasi — itu
    // detail internal, bukan untuk pembeli.
    const bocor =
      "You must enable Billing on the Google Cloud Project at https://console.cloud.google.com/project/rahasia-123/billing";
    const v = interpretGoogleStatus("REQUEST_DENIED");
    assert.doesNotMatch(String(v.error), /console\.cloud\.google\.com/);
    assert.doesNotMatch(String(v.error), /rahasia-123/);
    assert.doesNotMatch(String(v.error), /Billing/i);
    // Tapi log server WAJIB memuatnya supaya bisa didiagnosis.
    const line = googleStatusLogLine("autocomplete", "REQUEST_DENIED", bocor);
    assert.match(line, /REQUEST_DENIED/);
    assert.match(line, /console\.cloud\.google\.com/);
    assert.match(line, /places\/autocomplete/);
  });

  it("log memotong pesan panjang dan tahan status non-string", () => {
    const line = googleStatusLogLine("details", undefined, "x".repeat(500));
    assert.match(line, /tanpa status/);
    assert.ok(line.length < 300, "pesan panjang harus dipotong");
  });
});
