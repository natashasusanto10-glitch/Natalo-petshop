import type { ReactNode } from "react";

/**
 * PageHeader — title + subtitle + action slot konsisten untuk top of
 * admin page. Gantiin pattern manual div flex yang muncul di setiap page.
 *
 * Layout responsive:
 *   - Mobile: stacked (title above actions)
 *   - md+:    horizontal (actions right-aligned)
 */
type PageHeaderProps = {
  title: string;
  subtitle?: string;
  /** CTA buttons / link, biasanya max 2-3. */
  actions?: ReactNode;
};

export function PageHeader({ title, subtitle, actions }: PageHeaderProps) {
  return (
    <div className="flex flex-col items-start justify-between gap-3 md:flex-row md:items-center md:gap-4">
      <div className="min-w-0">
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
          {title}
        </h1>
        {subtitle ? (
          <p className="mt-1.5 text-sm text-zinc-600">{subtitle}</p>
        ) : null}
      </div>
      {actions ? (
        <div className="flex shrink-0 flex-wrap items-center gap-2">
          {actions}
        </div>
      ) : null}
    </div>
  );
}
