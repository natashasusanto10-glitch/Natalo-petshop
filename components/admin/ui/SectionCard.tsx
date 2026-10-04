import Link from "next/link";
import type { ReactNode } from "react";

/**
 * SectionCard — wrapper konsisten untuk content section di admin pages.
 * Header punya title + optional subtitle + optional action (CTA atau link
 * "Lihat semua →"). Body slot untuk apapun (list, tabel, form, dst).
 *
 * Padding & border-radius standardized — gantiin pattern manual
 * `rounded-lg border border-zinc-200 p-4` yang muncul puluhan kali di
 * codebase. Mudah di-update global kalau mau ubah design language.
 */
type SectionCardProps = {
  title: string;
  subtitle?: string;
  icon?: ReactNode;
  action?: {
    label: string;
    href: string;
  };
  children: ReactNode;
  /** Padding internal — `tight` untuk list yang sudah punya divide, `normal` default. */
  density?: "tight" | "normal";
  className?: string;
};

export function SectionCard({
  title,
  subtitle,
  icon,
  action,
  children,
  density = "normal",
  className = "",
}: SectionCardProps) {
  return (
    <section className={`admin-section ${className}`}>
      <header className="flex items-start justify-between gap-3 border-b border-zinc-100 px-4 py-4 md:px-5 md:py-5">
        <div className="flex min-w-0 items-start gap-3">
          {icon ? (
            <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-natalo-50 text-natalo-600">
              {icon}
            </span>
          ) : null}
          <div className="min-w-0">
            <h2 className="admin-heading text-base">{title}</h2>
            {subtitle ? (
              <p className="mt-0.5 text-xs text-zinc-500 md:text-sm">
                {subtitle}
              </p>
            ) : null}
          </div>
        </div>
        {action ? (
          <Link href={action.href} className="admin-section-action">
            {action.label} →
          </Link>
        ) : null}
      </header>
      <div className={density === "tight" ? "" : "admin-section-body"}>
        {children}
      </div>
    </section>
  );
}
