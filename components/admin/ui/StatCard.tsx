import Link from "next/link";
import type { ReactNode } from "react";
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
  trend?: { value: number; suffix?: string };
};
export function StatCard({
  label,
  value,
  helper,
  href,
  icon,
  variant = "default",
  trend,
}: StatCardProps) {
  const body = (
    <>
      <div className="admin-stat-top">
        <p>{label}</p>
        {icon && (
          <span className="admin-stat-icon" aria-hidden="true">
            {icon}
          </span>
        )}
      </div>
      <p className="admin-stat-value">
        {typeof value === "number"
          ? new Intl.NumberFormat("id-ID").format(value)
          : value}
      </p>
      <div className="admin-stat-bottom">
        {helper && <p>{helper}</p>}
        {trend && (
          <span
            className={`admin-stat-trend ${
              trend.value > 0 ? "is-up" : trend.value < 0 ? "is-down" : ""
            }`}
          >
            <span aria-hidden="true">
              {trend.value > 0 ? "↑" : trend.value < 0 ? "↓" : "·"}
            </span>
            <span className="sr-only">
              {trend.value > 0
                ? "Naik "
                : trend.value < 0
                ? "Turun "
                : "Tidak berubah "}
            </span>
            {new Intl.NumberFormat("id-ID", {
              maximumFractionDigits: 1,
            }).format(Math.abs(trend.value))}
            {trend.suffix ?? "%"}
          </span>
        )}
      </div>
    </>
  );
  const className = `admin-stat-card admin-stat-${variant}${
    href ? " admin-stat-link" : ""
  }`;
  return href ? (
    <Link href={href} className={className}>
      {body}
    </Link>
  ) : (
    <div className={className}>{body}</div>
  );
}
