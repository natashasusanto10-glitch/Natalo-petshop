export function formatRupiah(amount: number) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: "IDR",
    maximumFractionDigits: 0,
  }).format(amount);
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
