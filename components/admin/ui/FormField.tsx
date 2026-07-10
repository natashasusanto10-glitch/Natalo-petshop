import type { ReactNode } from "react";

/**
 * FormField — pembungkus label + penanda wajib + hint/error yang konsisten
 * untuk field form admin. Kontrol (input/select/textarea/komponen custom)
 * dilewatkan sebagai children. Menggantikan wrapper `Section`/label manual
 * yang gayanya sempat beda antar halaman (bobot font, penanda `•` vs `*`).
 *
 * Contoh:
 *   <FormField label="Nama Produk" required>
 *     <input ... />
 *   </FormField>
 */
export function FormField({
  label,
  required = false,
  hint,
  error,
  htmlFor,
  children,
}: {
  label: string;
  required?: boolean;
  hint?: string;
  error?: string;
  htmlFor?: string;
  children: ReactNode;
}) {
  return (
    <div>
      <label
        htmlFor={htmlFor}
        className="block text-sm font-semibold text-zinc-700"
      >
        {label}
        {required && <span className="ml-1 text-red-500">*</span>}
      </label>
      <div className="mt-1.5">{children}</div>
      {error ? (
        <p className="mt-1 text-xs text-red-500">{error}</p>
      ) : hint ? (
        <p className="mt-1 text-xs text-zinc-500">ⓘ {hint}</p>
      ) : null}
    </div>
  );
}
