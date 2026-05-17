import type { ReactNode } from "react";

export function LegalPage({
  title,
  updated,
  children,
  showHeading = true,
}: {
  title: string;
  updated: string;
  children: ReactNode;
  showHeading?: boolean;
}) {
  return (
    <div className="mx-auto max-w-3xl px-6 py-6 pb-20">
      {showHeading && (
        <div className="mb-8">
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 sm:text-3xl">
            {title}
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            Terakhir diperbarui: {updated}
          </p>
        </div>
      )}
      {!showHeading && (
        <p className="mb-6 text-sm font-semibold text-zinc-500">
          Terakhir diperbarui: {updated}
        </p>
      )}
      <div className="space-y-6 text-sm leading-relaxed text-zinc-700 sm:text-base">
        {children}
      </div>
    </div>
  );
}

export function Section({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section>
      <h2 className="mb-2 text-base font-bold text-zinc-950 sm:text-lg">
        {title}
      </h2>
      <div className="text-zinc-700">{children}</div>
    </section>
  );
}

export function Steps({
  items,
}: {
  items: { n: string; title: string; desc: string }[];
}) {
  return (
    <div className="space-y-4">
      {items.map((item) => (
        <div key={item.n} className="flex gap-4">
          <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-natalo-100 text-sm font-bold text-natalo-800">
            {item.n}
          </div>
          <div className="flex-1">
            <div className="mb-1 text-sm font-bold text-zinc-950 sm:text-base">
              {item.title}
            </div>
            <div className="text-sm leading-relaxed text-zinc-600">
              {item.desc}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
