import type { ReactNode } from "react";

/**
 * Full-width workspace content with shared responsive gutters.
 * Keep the legacy maxWidth hint for existing callers, but do not cap the
 * outer page: tables, forms and dashboards all use the available workspace.
 * Size individual inputs, previews and dialogs within their own components.
 */
type AdminPageWidth = "md" | "lg" | "xl" | "full";

export function AdminPage({
  maxWidth = "full",
  className = "",
  children,
}: {
  maxWidth?: AdminPageWidth;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div
      data-content-size={maxWidth}
      className={`admin-page min-w-0 w-full max-w-none ${className}`.trim()}
    >
      {children}
    </div>
  );
}
