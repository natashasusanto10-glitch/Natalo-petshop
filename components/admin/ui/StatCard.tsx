import Link from "next/link";
import type { ReactNode } from "react";

/**
 * StatCard — KPI card untuk dashboard admin.
 *
 * Design language: Shopee-vibrant + Natalo blue primary. Card punya
 * accent border-left berwarna sesuai variant + icon optional di kanan
 * atas. Hover lift halus + shadow grow untuk feedback klik-able.
 *
 * Variants:
 *   - `default` — netral, label biasa (stok normal, voucher aktif)
 *   - `primary` — natalo blue (highlight order baru / fokus utama)
 *   - `success` — emerald (sales hari ini, target tercapai)
 *   - `warning` — amber (stok menipis, voucher expiring)
 *   - `danger`  — red (stok habis, abuse flag)
 *   - `accent`  — orange (promo, broadcast — warm CTA)
 *
 * `value` boleh string (mis. "Rp 1.234.000") atau number — number
 * di-format dengan thousand separator otomatis.
 */
export type StatCardVariant =
  | "default"
  | "primary"
  | "success"
  | "warning"
  | "danger"
  | "accent";

type StatCardProps = {
  label: string;
  value: string | number;
  helper?: string;
  href?: string;
  icon?: ReactNode;
  variant?: StatCardVariant;
  /** Trend badge — angka relative ke periode sebelumnya. Positif = naik. */
  trend?: { value: number; suffix?: string };
};

const VARIANT_STYLES: Record<
  StatCardVariant,
  { border: string; iconBg: string; iconText: string; valueText: string }
> = {
  default: {
    border: "border-l-zinc-300",
    iconBg: "bg-zinc-100",
    iconText: "text-zinc-600",
    valueText: "text-zinc-950",
  },
  primary: {
    border: "border-l-natalo-500",
    iconBg: "bg-natalo-50",
    iconText: "text-natalo-600",
    valueText: "text-natalo-900",
  },
  success: {
    border: "border-l-emerald-500",
    iconBg: "bg-emerald-50",
    iconText: "text-emerald-600",
    valueText: "text-emerald-900",
  },
  warning: {
    border: "border-l-amber-500",
    iconBg: "bg-amber-50",
    iconText: "text-amber-700",
    valueText: "text-amber-900",
  },
  danger: {
    border: "border-l-red-500",
    iconBg: "bg-red-50",
    iconText: "text-red-600",
    valueText: "text-red-900",
  },
  accent: {
    border: "border-l-orange-500",
    iconBg: "bg-orange-50",
    iconText: "text-orange-600",
    valueText: "text-orange-900",
  },
};

function formatValue(value: string | number) {
  if (typeof value === "string") return value;
  return new Intl.NumberFormat("id-ID").format(value);
}

export function StatCard({
  label,
  value,
  helper,
  href,
  icon,
  variant = "default",
  trend,
}: StatCardProps) {
  const styles = VARIANT_STYLES[variant];

  const body = (
    <>
      <div className="flex items-start justify-between gap-3">
        <p className="text-[10px] font-black uppercase tracking-wider text-zinc-500 md:text-[11px]">
          {label}
        </p>
        {icon ? (
          <span
            className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg ${styles.iconBg} ${styles.iconText}`}
            aria-hidden="true"
          >
            {icon}
          </span>
        ) : null}
      </div>
      <p
        className={`mt-2.5 text-2xl font-black tracking-tight md:mt-3 md:text-[28px] ${styles.valueText}`}
      >
        {formatValue(value)}
      </p>
      <div className="mt-1 flex items-center gap-2">
        {helper ? (
          <p className="text-[11px] font-medium text-zinc-500 md:text-xs">
            {helper}
          </p>
        ) : null}
        {trend ? (
          <span
            className={`inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-[10px] font-bold ${
              trend.value > 0
                ? "bg-emerald-50 text-emerald-700"
                : trend.value < 0
                ? "bg-red-50 text-red-700"
                : "bg-zinc-100 text-zinc-600"
            }`}
          >
            {trend.value > 0 ? "↑" : trend.value < 0 ? "↓" : "·"}
            {Math.abs(trend.value)}
            {trend.suffix ?? "%"}
          </span>
        ) : null}
      </div>
    </>
  );

  const baseClass = `group relative block overflow-hidden rounded-2xl border border-zinc-200 border-l-4 bg-white p-4 transition duration-200 md:p-5 ${styles.border}`;

  if (href) {
    return (
      <Link
        href={href}
        className={`${baseClass} hover:-translate-y-0.5 hover:border-zinc-300 hover:shadow-[0_10px_30px_-12px_rgba(0,0,0,0.15)] active:translate-y-0`}
      >
        {body}
      </Link>
    );
  }

  return <div className={baseClass}>{body}</div>;
}
