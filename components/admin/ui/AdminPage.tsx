import type { ReactNode } from "react";

/**
 * AdminPage — pembungkus konten halaman admin: max-width + gutter + padding
 * vertikal yang konsisten. Menggantikan `mx-auto max-w-... px-4 py-...` yang
 * sebelumnya dirakit beda-beda tiap halaman (2xl…7xl acak).
 *
 * Tier lebar:
 *   - "md" (max-w-2xl)  → form/detail sempit
 *   - "lg" (max-w-4xl)  → daftar/detail sedang
 *   - "xl" (max-w-6xl)  → tabel lebar / dashboard (default)
 */
type AdminPageWidth = "md" | "lg" | "xl";

const WIDTH_CLASSES: Record<AdminPageWidth, string> = {
  md: "max-w-2xl",
  lg: "max-w-4xl",
  xl: "max-w-6xl",
};

export function AdminPage({
  maxWidth = "xl",
  className = "",
  children,
}: {
  maxWidth?: AdminPageWidth;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div
      className={`mx-auto w-full px-4 py-5 md:py-8 ${WIDTH_CLASSES[maxWidth]} ${className}`.trim()}
    >
      {children}
    </div>
  );
}
