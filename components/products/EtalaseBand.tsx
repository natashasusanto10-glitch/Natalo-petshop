import Link from "next/link";
import Image from "next/image";

type Crumb = { label: string; href?: string };

type Props = {
  heading: string;
  tagline: string;
  meta?: string[];
  breadcrumb?: Crumb[];
  thumbnailUrl?: string | null;
  className?: string;
};

export function EtalaseBand({
  heading,
  tagline,
  meta = [],
  breadcrumb = [],
  thumbnailUrl,
  className = "",
}: Props) {
  return (
    <section
      className={`relative overflow-hidden rounded-[var(--radius-xl)] border border-natalo-100 bg-gradient-to-br from-natalo-50 to-white px-5 py-5 md:px-7 md:py-6 ${className}`}
    >
      <div className="relative z-10 max-w-2xl">
        {breadcrumb.length > 0 && (
          <nav className="mb-2 flex flex-wrap items-center gap-1.5 text-xs font-semibold text-natalo-600">
            {breadcrumb.map((c, i) => (
              <span key={`${c.label}-${i}`} className="flex items-center gap-1.5">
                {i > 0 && <span className="text-natalo-300">/</span>}
                {c.href ? (
                  <Link href={c.href} className="transition hover:text-natalo-800">
                    {c.label}
                  </Link>
                ) : (
                  <span className="text-natalo-800">{c.label}</span>
                )}
              </span>
            ))}
          </nav>
        )}
        <h1 className="text-2xl font-extrabold tracking-tight text-natalo-900 md:text-3xl">
          {heading}
        </h1>
        <p className="mt-1.5 max-w-prose text-sm text-zinc-600 md:text-[15px]">
          {tagline}
        </p>
        {meta.length > 0 && (
          <p className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs font-semibold text-natalo-700">
            {meta.map((m, i) => (
              <span key={`${m}-${i}`} className="flex items-center gap-2">
                {i > 0 && <span className="text-natalo-300">·</span>}
                {m}
              </span>
            ))}
          </p>
        )}
      </div>

      {thumbnailUrl && (
        <div className="pointer-events-none absolute -right-6 -top-6 hidden h-40 w-40 rotate-6 overflow-hidden rounded-3xl opacity-[0.14] md:block">
          <Image src={thumbnailUrl} alt="" fill sizes="160px" className="object-cover" />
        </div>
      )}

      {/* static shelf-line — the unifying 2px natalo accent at the band base */}
      <span
        aria-hidden="true"
        className="absolute inset-x-0 bottom-0 h-0.5 bg-gradient-to-r from-transparent via-natalo-500 to-transparent"
      />
    </section>
  );
}
