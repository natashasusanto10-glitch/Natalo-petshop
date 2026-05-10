export function formatRupiah(amount: number) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: "IDR",
    maximumFractionDigits: 0,
  }).format(amount);
}

/**
 * Translate Biteship-style English duration strings ke frasa Bahasa Indonesia
 * yang lebih natural untuk user.
 *
 * Contoh:
 *   "1 - 2 Hours"  → "Tiba dalam 1–2 jam"
 *   "1 Day"        → "Tiba dalam 1 hari"
 *   "1 - 3 Days"   → "Tiba dalam 1–3 hari"
 *   "Same day"     → "Tiba hari ini"
 *   "Next day"     → "Tiba besok"
 *
 * Kalau tidak match pola yang dikenal, return string asli (fallback aman).
 */
export function formatShippingDuration(en: string | null | undefined): string {
  if (!en) return "";
  const raw = String(en).trim();
  if (!raw) return "";

  const lower = raw.toLowerCase();
  if (lower === "same day" || lower === "sameday") return "Tiba hari ini";
  if (lower === "next day" || lower === "nextday") return "Tiba besok";

  // Pola "X Hour(s)" / "X - Y Hour(s)" / "X-Y Hour(s)"
  const hour = lower.match(/^(\d+)(?:\s*[-–]\s*(\d+))?\s*hours?$/);
  if (hour) {
    const a = hour[1];
    const b = hour[2];
    return b ? `Tiba dalam ${a}–${b} jam` : `Tiba dalam ${a} jam`;
  }

  // Pola "X Day(s)" / "X - Y Day(s)"
  const day = lower.match(/^(\d+)(?:\s*[-–]\s*(\d+))?\s*days?$/);
  if (day) {
    const a = day[1];
    const b = day[2];
    return b ? `Tiba dalam ${a}–${b} hari` : `Tiba dalam ${a} hari`;
  }

  // Pola "X Minute(s)" — jarang tapi mungkin
  const minute = lower.match(/^(\d+)(?:\s*[-–]\s*(\d+))?\s*minutes?$/);
  if (minute) {
    const a = minute[1];
    const b = minute[2];
    return b ? `Tiba dalam ${a}–${b} menit` : `Tiba dalam ${a} menit`;
  }

  return raw;
}

export function createOrderNumber() {
  const date = new Date();
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  const rand = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `ORD-${y}${m}${d}-${rand}`;
}

const JAKARTA_TZ = "Asia/Jakarta";

function jakartaDateParts(date: Date) {
  // en-CA locale → YYYY-MM-DD numeric parts that we can reassemble safely
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: JAKARTA_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = fmt.formatToParts(date);
  const y = parts.find((p) => p.type === "year")!.value;
  const m = parts.find((p) => p.type === "month")!.value;
  const d = parts.find((p) => p.type === "day")!.value;
  return { y, m, d };
}

// Range "hari ini" relatif ke Asia/Jakarta (UTC+7), bukan timezone server.
// Penting untuk dashboard agar angka hari ini tetap konsisten saat deploy ke UTC.
export function jakartaTodayRange(reference: Date = new Date()) {
  const { y, m, d } = jakartaDateParts(reference);
  return {
    start: new Date(`${y}-${m}-${d}T00:00:00+07:00`),
    end: new Date(`${y}-${m}-${d}T23:59:59.999+07:00`),
  };
}

export function jakartaDayRange(daysAgo: number, reference: Date = new Date()) {
  const shifted = new Date(reference.getTime() - daysAgo * 24 * 60 * 60 * 1000);
  const { y, m, d } = jakartaDateParts(shifted);
  return {
    start: new Date(`${y}-${m}-${d}T00:00:00+07:00`),
    end: new Date(`${y}-${m}-${d}T23:59:59.999+07:00`),
  };
}
