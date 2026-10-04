"use client";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { AdminDialog } from "./ui/AdminDialog";
import { NumberInput } from "./ui/NumberInput";
import { Button, useAdminToast } from "./ui";
import { QuickEditPencil } from "./InlineEditCell";
import { formatAdminNumber, parseAdminInteger } from "@/lib/admin/number-input";

type VariantAttribute = {
  id: string;
  name: string;
  options: Array<{ id: string; value: string }>;
};
type Variant = {
  id: string;
  sku: string | null;
  price: number;
  stock: number;
  isActive?: boolean;
  options: Array<{ optionId: string }>;
};
type Props = {
  productId: string;
  productName: string;
  field: "price" | "stock";
  initialValue: number;
  variantId?: string;
};
function variantLabel(variant: Variant, attributes: VariantAttribute[]) {
  return (
    attributes
      .flatMap((attr) =>
        attr.options
          .filter((option) =>
            variant.options.some((ref) => ref.optionId === option.id)
          )
          .map((option) => option.value)
      )
      .join(" / ") ||
    variant.sku ||
    "Varian"
  );
}
export function VariantInlineEditCell({
  productId,
  productName,
  field,
  initialValue,
  variantId,
}: Props) {
  const formRef = useRef<HTMLFormElement>(null);
  const router = useRouter();
  const { show } = useAdminToast();
  const [value, setValue] = useState(initialValue),
    [open, setOpen] = useState(false),
    [loading, setLoading] = useState(false),
    [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null),
    [attributes, setAttributes] = useState<VariantAttribute[]>([]),
    [variants, setVariants] = useState<Variant[]>([]),
    [drafts, setDrafts] = useState<Record<string, string>>({}),
    [bulkValue, setBulkValue] = useState("");
  const [reload, setReload] = useState(0),
    [message, setMessage] = useState("");
  const label = field === "price" ? "harga" : "stok";
  useEffect(() => setValue(initialValue), [initialValue]);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    setVariants([]);
    setDrafts({});
    void (async () => {
      try {
        const response = await fetch(
          `/api/admin/products/${productId}/variants`,
          { signal: controller.signal }
        );
        const data = await response.json();
        if (!response.ok)
          throw new Error(data?.error ?? "Varian gagal dimuat.");
        if (controller.signal.aborted) return;
        const next: Variant[] = (data.variants ?? []).filter(
          (row: Variant) => !variantId || row.id === variantId
        );
        if (!next.length)
          throw new Error("Tidak ada varian yang dapat diedit.");
        setAttributes(data.attributes ?? []);
        setVariants(next);
        setDrafts(
          Object.fromEntries(next.map((row) => [row.id, String(row[field])]))
        );
      } catch (err) {
        if (!controller.signal.aborted)
          setError(err instanceof Error ? err.message : "Varian gagal dimuat.");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    })();
    return () => controller.abort();
  }, [open, productId, field, variantId, reload]);
  useEffect(() => {
    if (open && !loading && variants.length)
      formRef.current
        ?.querySelector<HTMLInputElement>("input:not([disabled])")
        ?.focus();
  }, [open, loading, variants.length]);
  const valid = (raw: string) => {
    const number = parseAdminInteger(raw);
    return (
      Number.isSafeInteger(number) &&
      number >= (field === "price" ? 1 : 0) &&
      number <= (field === "price" ? 999999999 : 999999)
    );
  };
  async function save() {
    if (
      !variants.length ||
      variants.some((row) => !valid(drafts[row.id] ?? ""))
    ) {
      setError(`Isi ${label} setiap varian dengan bilangan bulat yang valid.`);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const updates = variants
        .filter((row) => parseAdminInteger(drafts[row.id]) !== row[field])
        .map((row) => ({
          id: row.id,
          [field]: parseAdminInteger(drafts[row.id]),
        }));
      if (updates.length) {
        const response = await fetch(
          `/api/admin/products/${productId}/variants/bulk`,
          {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ updates }),
          }
        );
        const data = await response.json().catch(() => null);
        if (!response.ok)
          throw new Error(
            data?.error ?? "Perubahan gagal disimpan. Coba lagi."
          );
        const next = variantId
          ? parseAdminInteger(drafts[variantId])
          : data.aggregate?.[field];
        if (typeof next === "number") setValue(next);
        show(
          `${field === "price" ? "Harga" : "Stok"} varian berhasil diperbarui.`
        );
        router.refresh();
      }
      setOpen(false);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Perubahan gagal disimpan."
      );
    } finally {
      setSaving(false);
    }
  }
  return (
    <>
      <button
        type="button"
        className="admin-quick-value"
        aria-label={`Atur ${label} ${productName}`}
        onClick={() => {
          setBulkValue("");
          setMessage("");
          setOpen(true);
        }}
      >
        <span>{formatAdminNumber(value)}</span>
        <QuickEditPencil />
      </button>
      <AdminDialog
        open={open}
        title={`Atur ${label} variasi`}
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
              form={`variants-${field}-${productId}-${variantId ?? "all"}`}
              disabled={loading || saving || !variants.length}
            >
              {saving ? "Menyimpan…" : "Simpan"}
            </Button>
          </>
        }
      >
        <p className="mb-5 text-sm text-slate-600">{productName}</p>
        {loading ? (
          <p role="status" className="text-sm text-slate-500">
            Memuat varian…
          </p>
        ) : (
          <form
            ref={formRef}
            id={`variants-${field}-${productId}-${variantId ?? "all"}`}
            onSubmit={(event) => {
              event.preventDefault();
              if (!saving) void save();
            }}
          >
            {!variantId && variants.length > 1 && (
              <div className="mb-5 flex flex-wrap items-end gap-3 rounded-lg bg-slate-50 p-4">
                <label className="min-w-0 flex-1">
                  <span className="admin-field-label">Ubah semua variasi</span>
                  <NumberInput
                    aria-label={`Ubah semua ${label} variasi`}
                    value={bulkValue}
                    thousands={field === "price"}
                    onValueChange={setBulkValue}
                    disabled={saving}
                    className="admin-field-control"
                  />
                </label>
                <Button
                  type="button"
                  variant="secondary"
                  disabled={saving || !bulkValue}
                  onClick={() => {
                    if (!valid(bulkValue)) {
                      setError(`Nilai ${label} tidak valid.`);
                      return;
                    }
                    setDrafts(
                      Object.fromEntries(
                        variants.map((row) => [row.id, bulkValue])
                      )
                    );
                    setError(null);
                    setMessage(
                      `Diterapkan ke ${variants.length} varian. Klik Simpan untuk menyimpan perubahan.`
                    );
                  }}
                >
                  Terapkan ke semua
                </Button>
              </div>
            )}
            {message && (
              <p role="status" className="mb-3 text-xs text-blue-700">
                {message}
              </p>
            )}
            <div className="space-y-3">
              {variants.map((row) => (
                <label
                  key={row.id}
                  className="grid grid-cols-[minmax(0,1fr)_minmax(110px,1fr)] items-center gap-4 border-b border-slate-100 pb-3"
                >
                  <span className="text-sm">
                    {variantLabel(row, attributes)}
                    {row.isActive === false && (
                      <span className="mt-1 block text-xs text-slate-500">
                        Tidak aktif
                      </span>
                    )}
                  </span>
                  <NumberInput
                    aria-label={`${label} ${variantLabel(row, attributes)}`}
                    value={drafts[row.id] ?? ""}
                    thousands={field === "price"}
                    onValueChange={(next) =>
                      setDrafts((current) => ({ ...current, [row.id]: next }))
                    }
                    disabled={saving}
                    className="admin-field-control"
                  />
                </label>
              ))}
            </div>
          </form>
        )}
        {error && (
          <div role="alert" className="mt-4 text-sm text-red-700">
            <p>{error}</p>
            {!variants.length && !loading && (
              <Button
                type="button"
                variant="secondary"
                onClick={() => setReload((count) => count + 1)}
                className="mt-3"
              >
                Coba lagi
              </Button>
            )}
          </div>
        )}
      </AdminDialog>
    </>
  );
}
