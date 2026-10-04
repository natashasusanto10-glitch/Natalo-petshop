import { jakartaDayRange } from "@/lib/format";

export type RevenueBucket = { day: string; hour: number; total: number };
export type DashboardRevenue = {
  daily: Array<{ label: string; total: number }>;
  hourly: Array<{ label: string; total: number }>;
  todayTotal: number;
  yesterdayTotal: number;
  weekTotal: number;
  previousWeekTotal: number;
};

/** Order creation dates match the existing sales report, all in Jakarta time. */
export function buildDashboardRevenue(
  buckets: RevenueBucket[],
  now: Date
): DashboardRevenue {
  const keyFormatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const dayKey = (date: Date) => {
    const parts = keyFormatter.formatToParts(date);
    const value = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)!.value;
    return `${value("year")}-${value("month")}-${value("day")}`;
  };
  const totalForDay = (key: string) =>
    buckets
      .filter((bucket) => bucket.day === key)
      .reduce((sum, bucket) => sum + bucket.total, 0);
  const daily = Array.from({ length: 7 }, (_, index) => {
    const date = jakartaDayRange(6 - index, now).start;
    return {
      label: new Intl.DateTimeFormat("id-ID", {
        timeZone: "Asia/Jakarta",
        day: "numeric",
        month: "short",
      }).format(date),
      total: totalForDay(dayKey(date)),
    };
  });
  const today = dayKey(now);
  const currentHour = Number(
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Asia/Jakarta",
      hour: "2-digit",
      hourCycle: "h23",
    }).format(now)
  );
  let cumulative = 0;
  const hourly = Array.from({ length: currentHour + 1 }, (_, hour) => {
    cumulative += buckets
      .filter((bucket) => bucket.day === today && bucket.hour === hour)
      .reduce((sum, bucket) => sum + bucket.total, 0);
    return { label: `${String(hour).padStart(2, "0")}.00`, total: cumulative };
  });
  return {
    daily,
    hourly,
    todayTotal: totalForDay(today),
    yesterdayTotal: totalForDay(dayKey(jakartaDayRange(1, now).start)),
    weekTotal: daily.reduce((sum, day) => sum + day.total, 0),
    previousWeekTotal: Array.from({ length: 7 }, (_, index) =>
      totalForDay(dayKey(jakartaDayRange(7 + index, now).start))
    ).reduce((sum, value) => sum + value, 0),
  };
}
