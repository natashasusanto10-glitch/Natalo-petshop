import Link from "next/link";

type Props = {
  title: string;
  subtitle?: string;
  href?: string;
  ctaLabel?: string;
};

export function SectionHeader({ title, subtitle, href, ctaLabel = "Lihat Semua" }: Props) {
  return (
    <div className="mb-4 flex items-end justify-between gap-4">
      <div className="min-w-0">
        <h2 className="text-lg font-extrabold tracking-tight text-zinc-900 sm:text-xl md:text-2xl">
          {title}
        </h2>
        {subtitle && (
          <p className="mt-0.5 truncate text-xs text-zinc-500 sm:text-sm">{subtitle}</p>
        )}
      </div>
      {href && (
        <Link
          href={href}
          className="shrink-0 text-sm font-bold text-natalo-500 transition hover:text-natalo-700"
        >
          {ctaLabel} →
        </Link>
      )}
    </div>
  );
}
