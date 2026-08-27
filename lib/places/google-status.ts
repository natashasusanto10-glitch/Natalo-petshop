/**
 * Penerjemah status Google Maps/Places → hasil HTTP kita.
 *
 * MASALAH YANG DIPERBAIKI: Google membalas **HTTP 200** walau permintaan
 * ditolak — kegagalannya hanya ada di field `status` dalam body. Ketiga
 * rute places dulu meneruskan apa adanya dengan
 * `status: googleResponse.ok ? 200 : 502`, sehingga:
 *
 *   REQUEST_DENIED + predictions: []  →  HTTP 200, daftar kosong
 *
 * Di app itu tampil identik dengan "alamat tidak ditemukan". Pengguna
 * tidak bisa membedakan pencarian nihil dari layanan mati, dan TIDAK ADA
 * jejak apa pun di log/Sentry. Terbukti di produksi 2026-08-27: billing
 * Google nonaktif, pencarian alamat mati total, nol alarm.
 *
 * `ZERO_RESULTS` sengaja TETAP dianggap sukses — itu memang jawaban sah
 * "tidak ada yang cocok", bukan kegagalan.
 */
export type GoogleStatusVerdict = {
  ok: boolean;
  /** Status HTTP yang harus dikembalikan rute kita. */
  httpStatus: number;
  /** Pesan siap-tampil untuk pengguna (null kalau ok). */
  error: string | null;
  /** True kalau ini salah konfigurasi milik kita, bukan salah pengguna. */
  isConfigError: boolean;
};

const OK_STATUSES = new Set(["OK", "ZERO_RESULTS"]);

export function interpretGoogleStatus(status: unknown): GoogleStatusVerdict {
  const s = typeof status === "string" ? status : "";
  if (OK_STATUSES.has(s)) {
    return { ok: true, httpStatus: 200, error: null, isConfigError: false };
  }

  switch (s) {
    // Billing mati, API belum diaktifkan, kunci dibatasi/salah. Semuanya
    // salah konfigurasi kita — pengguna tidak bisa berbuat apa-apa.
    case "REQUEST_DENIED":
      return {
        ok: false,
        httpStatus: 503,
        error: "Layanan pencarian alamat sedang tidak tersedia. Silakan isi alamat secara manual.",
        isConfigError: true,
      };
    // Kuota harian habis / rate limit dari sisi Google.
    case "OVER_QUERY_LIMIT":
      return {
        ok: false,
        httpStatus: 503,
        error: "Pencarian alamat sedang sibuk. Coba lagi sebentar lagi.",
        isConfigError: true,
      };
    // Parameter yang kita kirim salah — bug kita, bukan pengguna.
    case "INVALID_REQUEST":
      return {
        ok: false,
        httpStatus: 400,
        error: "Permintaan pencarian alamat tidak valid.",
        isConfigError: true,
      };
    case "NOT_FOUND":
      return {
        ok: false,
        httpStatus: 404,
        error: "Alamat tidak ditemukan.",
        isConfigError: false,
      };
    // Termasuk status yang belum dikenal DAN respons tanpa `status` sama
    // sekali (mis. body Google berubah bentuk). Pesan asli Google sengaja
    // TIDAK diteruskan ke pengguna — bisa memuat nama project atau
    // petunjuk kunci; cukup dicatat lewat googleStatusLogLine.
    default:
      return {
        ok: false,
        httpStatus: 502,
        error: "Layanan pencarian alamat sedang bermasalah.",
        isConfigError: true,
      };
  }
}

/**
 * Ringkasan aman untuk log server. Pesan Google dipotong dan TIDAK
 * pernah dikirim ke klien — bisa memuat nama project atau petunjuk kunci.
 */
export function googleStatusLogLine(
  endpoint: string,
  status: unknown,
  errorMessage?: unknown,
): string {
  const s = typeof status === "string" ? status : "(tanpa status)";
  const m = typeof errorMessage === "string" ? errorMessage.slice(0, 200) : "";
  return `[places/${endpoint}] Google menolak: ${s}${m ? ` — ${m}` : ""}`;
}
