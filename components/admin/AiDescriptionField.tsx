"use client";

/**
 * AiDescriptionField — field "Deskripsi" di form edit produk dengan tombol
 * "✨ Generate deskripsi" (AI). Mirror pola AIVoucherSuggestButton (loading
 * state, error display, styling) tapi lebih sederhana: hasil generate
 * langsung menimpa textarea (controlled) tanpa modal preview, karena
 * outputnya cuma teks (bukan config form multi-field).
 *
 * Textarea tetap `name="description"` + `required` supaya form
 * server-action (`<form action={updateProduct}>`) tetap membacanya via
 * FormData seperti biasa.
 */
import { useState } from "react";
import { FormField } from "@/components/admin/ui";

export function AiDescriptionField({
  productId,
  defaultValue,
}: {
  productId: string;
  defaultValue: string;
}) {
  const [description, setDescription] = useState(defaultValue);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleGenerate = async (e: React.MouseEvent<HTMLButtonElement>) => {
    const form = e.currentTarget.form;
    const nameInput = form?.elements.namedItem("name") as HTMLInputElement | null;
    const currentName = nameInput?.value?.trim() ?? "";

    if (description.trim()) {
      if (!window.confirm("Timpa deskripsi yang ada dengan hasil AI?")) return;
    }

    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/admin/products/${productId}/generate-description`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: currentName || undefined }),
        },
      );
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        setError(data?.error ?? "Gagal generate deskripsi. Coba lagi.");
      } else {
        setDescription(data?.description ?? "");
      }
    } catch (err) {
      setError(
        err instanceof Error ? `Network error: ${err.message}` : "Network error",
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <FormField label="Deskripsi" required>
      <div className="mb-2 flex items-center gap-2">
        <button
          type="button"
          onClick={handleGenerate}
          disabled={loading}
          className="inline-flex items-center gap-1.5 rounded-lg border-2 border-purple-300 bg-purple-50 px-3 py-1.5 text-xs font-bold text-purple-800 hover:bg-purple-100 disabled:cursor-not-allowed disabled:border-zinc-200 disabled:bg-zinc-50 disabled:text-zinc-400"
        >
          {loading ? (
            <>
              <span
                className="h-3 w-3 animate-spin rounded-full border-2 border-purple-400 border-t-transparent"
                aria-hidden
              />
              Generating…
            </>
          ) : (
            <>
              <span>✨</span>
              Generate deskripsi
            </>
          )}
        </button>
        <span className="text-[11px] text-zinc-500">
          Dibuat AI dari nama, kategori, brand, varian — cek &amp; edit sebelum
          simpan.
        </span>
      </div>
      <textarea
        name="description"
        required
        value={description}
        onChange={(e) => setDescription(e.target.value)}
        rows={4}
        className="block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-600"
      />
      {error && <p className="mt-1 text-xs text-red-500">⚠️ {error}</p>}
    </FormField>
  );
}
