"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { AdminDialog } from "./ui/AdminDialog";
import { NumberInput } from "./ui/NumberInput";
import { Button, useAdminToast } from "./ui";
import { formatAdminNumber, parseAdminInteger } from "@/lib/admin/number-input";

type Props = {
  productId: string;
  field: "price" | "stock";
  initialValue: number;
  productName?: string;
  readOnly?: boolean;
  readOnlyHint?: string;
};
export function QuickEditPencil() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
    >
      <path d="m16 3 5 5-12 12-6 1 1-6ZM14 5l5 5" />
    </svg>
  );
}
export function InlineEditCell({
  productId,
  productName,
  field,
  initialValue,
  readOnly,
  readOnlyHint,
}: Props) {
  const router = useRouter();
  const { show } = useAdminToast();
  const [value, setValue] = useState(initialValue),
    [draft, setDraft] = useState(String(initialValue));
  const [open, setOpen] = useState(false),
    [saving, setSaving] = useState(false),
    [error, setError] = useState<string | null>(null);
  const label = field === "price" ? "harga" : "stok";
  useEffect(() => setValue(initialValue), [initialValue]);
  async function save() {
    const next = parseAdminInteger(draft),
      min = field === "price" ? 1 : 0,
      max = field === "price" ? 999999999 : 999999;
    if (!Number.isSafeInteger(next) || next < min || next > max) {
      setError(
        `Isi ${label} dengan bilangan bulat antara ${formatAdminNumber(
          min
        )} dan ${formatAdminNumber(max)}.`
      );
      return;
    }
    if (next === value) {
      setOpen(false);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const response = await fetch("/api/admin/products/bulk", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ updates: [{ id: productId, [field]: next }] }),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok)
        throw new Error(data?.error ?? "Perubahan gagal disimpan. Coba lagi.");
      setValue(next);
      setOpen(false);
      show(`${field === "price" ? "Harga" : "Stok"} berhasil diperbarui.`);
      router.refresh();
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Perubahan gagal disimpan."
      );
    } finally {
      setSaving(false);
    }
  }
  if (readOnly)
    return (
      <span title={readOnlyHint} className="text-sm text-slate-500">
        {formatAdminNumber(value)}
      </span>
    );
  return (
    <>
      <button
        type="button"
        className="admin-quick-value"
        aria-label={`Atur ${label}${productName ? ` ${productName}` : ""}`}
        onClick={() => {
          setDraft(String(value));
          setError(null);
          setOpen(true);
        }}
      >
        <span>{formatAdminNumber(value)}</span>
        <QuickEditPencil />
      </button>
      <AdminDialog
        open={open}
        title={`Atur ${label}`}
        busy={saving}
        onClose={() => setOpen(false)}
        footer={
          <>
            <Button
              type="button"
              variant="secondary"
              disabled={saving}
              onClick={() => setOpen(false)}
            >
              Batal
            </Button>
            <Button
              type="submit"
              form={`quick-${field}-${productId}`}
              disabled={saving}
            >
              {saving ? "Menyimpan…" : "Simpan"}
            </Button>
          </>
        }
      >
        {productName && (
          <p className="mb-5 text-sm text-slate-600">{productName}</p>
        )}
        <form
          id={`quick-${field}-${productId}`}
          onSubmit={(event) => {
            event.preventDefault();
            if (!saving) void save();
          }}
        >
          <label>
            <span className="admin-field-label">
              {field === "price" ? "Harga" : "Stok"}
            </span>
            <NumberInput
              autoFocus
              aria-invalid={Boolean(error)}
              value={draft}
              thousands={field === "price"}
              onValueChange={setDraft}
              disabled={saving}
              className="admin-field-control"
            />
          </label>
          {error && (
            <p role="alert" className="mt-3 text-sm text-red-700">
              {error}
            </p>
          )}
        </form>
      </AdminDialog>
    </>
  );
}
