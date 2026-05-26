import type { ReactNode } from "react";

/**
 * Badge — pill-style tag dengan semantic variant. Standardize warna +
 * size yang sebelumnya inline manual di banyak page (`bg-amber-100
 * text-amber-700 ...`).
 *
 * Variants:
 *   - `neutral`  — abu, default
 *   - `info`     — natalo blue, informational
 *   - `success`  — emerald, sudah ok / paid
 *   - `warning`  — amber, perlu attention
 *   - `danger`   — red, urgent / error
 *   - `accent`   — orange, promo / new
 *   - `purple`   — purple, refunded / system
 *
 * Helper: `STATUS_BADGE_VARIANT` & `PAY_BADGE_VARIANT` map untuk konsistensi
 * antara order status / payment status → variant warna.
 */
export type BadgeVariant =
  | "neutral"
  | "info"
  | "success"
  | "warning"
  | "danger"
  | "accent"
  | "purple";

const VARIANT_CLASSES: Record<BadgeVariant, string> = {
  neutral: "bg-zinc-100 text-zinc-700 ring-zinc-200",
  info: "bg-natalo-50 text-natalo-700 ring-natalo-200",
  success: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  warning: "bg-amber-50 text-amber-700 ring-amber-200",
  danger: "bg-red-50 text-red-700 ring-red-200",
  accent: "bg-orange-50 text-orange-700 ring-orange-200",
  purple: "bg-purple-50 text-purple-700 ring-purple-200",
};

type BadgeProps = {
  children: ReactNode;
  variant?: BadgeVariant;
  size?: "sm" | "md";
};

export function Badge({ children, variant = "neutral", size = "sm" }: BadgeProps) {
  const sizeClass =
    size === "md" ? "px-2.5 py-1 text-xs" : "px-2 py-0.5 text-[11px]";
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full font-bold ring-1 ring-inset ${VARIANT_CLASSES[variant]} ${sizeClass}`}
    >
      {children}
    </span>
  );
}

/** Map order.status → BadgeVariant. */
export const STATUS_BADGE_VARIANT: Record<string, BadgeVariant> = {
  PENDING: "warning",
  PAID: "success",
  PROCESSING: "info",
  READY_FOR_PICKUP: "success",
  SHIPPED: "info",
  DELIVERED: "success",
  CANCELLED: "danger",
  REFUNDED: "purple",
};

/** Map order.paymentStatus → BadgeVariant. */
export const PAY_BADGE_VARIANT: Record<string, BadgeVariant> = {
  UNPAID: "danger",
  PENDING: "warning",
  PAID: "success",
  FAILED: "danger",
  EXPIRED: "neutral",
  REFUNDED: "purple",
};
