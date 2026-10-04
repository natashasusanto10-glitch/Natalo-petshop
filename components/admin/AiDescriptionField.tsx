"use client";

/**
 * AiDescriptionField — field "Deskripsi" di form edit produk dengan tombol
 * "✨ Generate deskripsi" (AI). Mirror pola AIVoucherSuggestButton (loading
 * state, error display, styling) tapi lebih sederhana: hasil generate
 * mengganti textarea (controlled) setelah konfirmasi bila sudah terisi;
 * outputnya cuma teks (bukan config form multi-field).
 *
 * Textarea tetap `name="description"` + `required` supaya form
 * server-action (`<form action={updateProduct}>`) tetap membacanya via
 * FormData seperti biasa.
 */
import { useEffect, useRef, useState } from "react";
import { Button, ConfirmDialog, FormField } from "@/components/admin/ui";
import {
  buildGenerationPayload,
  type DescriptionContextInput,
} from "@/lib/ai/product-description-context";
export {
  buildGenerationPayload,
  buildDescriptionContext,
} from "@/lib/ai/product-description-context";

export type AiDescriptionFieldProps = {
  value?: string;
  onChange?: (value: string) => void;
  context?: DescriptionContextInput;
  existingProductId?: string;
  onBusyChange?: (busy: boolean) => void;
  /** Legacy edit props retained for existing callers. */
  productId?: string;
  defaultValue?: string;
};

export function AiDescriptionField({
  value,
  onChange,
  context,
  existingProductId,
  onBusyChange,
  productId,
  defaultValue,
}: AiDescriptionFieldProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [description, setDescription] = useState(value ?? defaultValue ?? "");
  const [loading, setLoading] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    onBusyChange?.(loading);
  }, [loading, onBusyChange]);
  useEffect(() => {
    if (value !== undefined) setDescription(value);
  }, [value]);

  const handleGenerate = async () => {
    const nameInput = textareaRef.current?.form?.elements.namedItem(
      "name"
    ) as HTMLInputElement | null;
    const currentName = context?.name?.trim() || nameInput?.value?.trim() || "";

    setLoading(true);
    setError(null);
    try {
      const productContext = buildGenerationPayload(
        context ?? { name: currentName },
        currentName
      );
      const endpoint =
        existingProductId ?? productId
          ? `/api/admin/products/${
              existingProductId ?? productId
            }/generate-description`
          : "/api/admin/products/generate-description";
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(productContext),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        // `data` null = respons bukan JSON kita, jadi ini error platform
        // (mis. 504 timeout fungsi), bukan error yang kita lempar sendiri.
        // Sebut statusnya — pesan generik menyembunyikan bedanya dan
        // bikin penyebabnya tak bisa dibedakan dari layar admin.
        setError(
          data?.error ??
            (res.status === 504
              ? "Riset produk kehabisan waktu di server (504). Coba lagi; kalau berulang, produk ini mungkin butuh deskripsi manual."
              : `Gagal generate deskripsi (HTTP ${res.status}). Coba lagi.`)
        );
      } else {
        const nextDescription = data?.description ?? "";
        setDescription(nextDescription);
        onChange?.(nextDescription);
      }
    } catch (err) {
      setError(
        err instanceof Error ? `Network error: ${err.message}` : "Network error"
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <FormField label="Deskripsi" required>
      <div className="mb-3 flex flex-wrap items-center gap-3">
        <Button
          type="button"
          variant="secondary"
          size="sm"
          onClick={() => {
            if (description.trim()) setConfirmOpen(true);
            else void handleGenerate();
          }}
          disabled={loading}
          className="shrink-0"
        >
          {loading ? (
            <>
              <span
                className="h-3 w-3 animate-spin rounded-full border-2 border-purple-400 border-t-transparent"
                aria-hidden
              />
              Membuat deskripsi…
            </>
          ) : (
            <>
              <span aria-hidden="true">✧</span>
              Generate deskripsi
            </>
          )}
        </Button>
        <span className="text-[11px] text-zinc-500">
          Dibuat AI dari nama, kategori, brand, varian — cek &amp; edit sebelum
          simpan.
        </span>
      </div>
      <textarea
        ref={textareaRef}
        disabled={loading}
        aria-label="Deskripsi produk"
        name="description"
        required
        value={description}
        onChange={(e) => {
          setDescription(e.target.value);
          onChange?.(e.target.value);
        }}
        rows={4}
        className="admin-field-control"
      />
      {error && (
        <p role="alert" className="mt-2 text-sm text-red-700">
          {error}
        </p>
      )}
      <ConfirmDialog
        open={confirmOpen}
        title="Ganti deskripsi dengan AI?"
        message="Deskripsi yang sudah diisi akan diganti. Hasilnya tetap dapat Anda edit sebelum produk disimpan."
        variant="primary"
        confirmLabel="Buat deskripsi"
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          setConfirmOpen(false);
          void handleGenerate();
        }}
      />
    </FormField>
  );
}
