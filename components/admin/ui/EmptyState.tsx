import Link from "next/link";
import type { ReactNode } from "react";

/**
 * EmptyState — friendly placeholder untuk list/section yang kosong.
 *
 * Pattern dipakai di:
 *   - Order list waktu gak ada pesanan perlu di-process
 *   - Product list kosong setelah filter
 *   - Review/voucher/feed kosong
 *   - Search result kosong
 *
 * Bukan blank screen + "Tidak ada data" plain text. Bantu admin tau apa
 * yang seharusnya muncul + apa next action (CTA optional).
 */
type EmptyStateProps = {
  /** Emoji atau icon JSX. Default 📭. */
  icon?: ReactNode;
  title: string;
  description?: string;
  action?: {
    label: string;
    href: string;
  };
  /** Size — `compact` untuk inline (di dalam SectionCard), `full` untuk standalone page. */
  size?: "compact" | "full";
};

export function EmptyState({
  icon = "📭",
  title,
  description,
  action,
  size = "compact",
}: EmptyStateProps) {
  const padding = size === "full" ? "py-16 md:py-20" : "py-10 md:py-12";
  const iconSize = size === "full" ? "text-5xl md:text-6xl" : "text-3xl md:text-4xl";
  const titleSize = size === "full" ? "text-lg md:text-xl" : "text-sm md:text-base";

  return (
    <div className={`flex flex-col items-center justify-center px-4 text-center ${padding}`}>
      <div className={`${iconSize} leading-none`} aria-hidden="true">
        {icon}
      </div>
      <p className={`mt-3 font-black text-zinc-900 ${titleSize}`}>{title}</p>
      {description ? (
        <p className="mt-1.5 max-w-xs text-xs text-zinc-500 md:text-sm">
          {description}
        </p>
      ) : null}
      {action ? (
        <Link
          href={action.href}
          className="mt-4 inline-flex items-center gap-2 rounded-full bg-natalo-500 px-4 py-2 text-xs font-bold text-white shadow-sm transition hover:bg-natalo-600 md:text-sm"
        >
          {action.label} →
        </Link>
      ) : null}
    </div>
  );
}
