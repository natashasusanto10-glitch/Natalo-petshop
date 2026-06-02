"use client";

import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";

type Field = "price" | "stock";

type VariantOption = {
  id: string;
  value: string;
  attributeId: string;
};

type VariantAttribute = {
  id: string;
  name: string;
  options: VariantOption[];
};

type Variant = {
  id: string;
  sku: string | null;
  price: number;
  stock: number;
  options: Array<{ optionId: string }>;
};

type Props = {
  productId: string;
  productName: string;
  field: Field;
  initialValue: number;
};

function formatNumber(n: number) {
  return Math.round(n).toLocaleString("id-ID");
}

function parseNumber(value: string) {
  const clean = value.replace(/\./g, "").replace(/[^\d]/g, "");
  return clean === "" ? 0 : Number(clean);
}

function variantLabel(variant: Variant, attributes: VariantAttribute[]) {
  const optionMap = new Map<string, { attr: string; value: string }>();
  for (const attr of attributes) {
    for (const option of attr.options) {
      optionMap.set(option.id, { attr: attr.name, value: option.value });
    }
  }

  const labels = variant.options
    .map((ref) => optionMap.get(ref.optionId))
    .filter((item): item is { attr: string; value: string } => Boolean(item))
    .map((item) => `${item.attr}: ${item.value}`);

  return labels.join(" / ") || variant.sku || "Varian";
}

export function VariantInlineEditCell({
  productId,
  productName,
  field,
  initialValue,
}: Props) {
  const [value, setValue] = useState(initialValue);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [attributes, setAttributes] = useState<VariantAttribute[]>([]);
  const [variants, setVariants] = useState<Variant[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});

  useEffect(() => {
    setValue(initialValue);
  }, [initialValue]);

  useEffect(() => {
    if (!savedAt) return;
    const t = setTimeout(() => setSavedAt(0), 2000);
    return () => clearTimeout(t);
  }, [savedAt]);

  async function openEditor() {
    setOpen(true);
    setError(null);
    setLoading(true);
    try {
      const res = await fetch(`/api/admin/products/${productId}/variants`);
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || "Gagal memuat varian");

      const nextVariants: Variant[] = data.variants || [];
      setAttributes(data.attributes || []);
      setVariants(nextVariants);
      setDrafts(
        Object.fromEntries(
          nextVariants.map((variant) => [
            variant.id,
            field === "price" ? formatNumber(variant.price) : String(variant.stock),
          ])
        )
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat varian");
    } finally {
      setLoading(false);
    }
  }

  function updateDraft(id: string, raw: string) {
    const clean = raw.replace(/\./g, "").replace(/[^\d]/g, "");
    setDrafts((current) => ({
      ...current,
      [id]: field === "price" && clean ? Number(clean).toLocaleString("id-ID") : clean,
    }));
  }

  async function save() {
    setSaving(true);
    setError(null);
    try {
      const updates = variants.map((variant) => ({
        id: variant.id,
        [field]: parseNumber(drafts[variant.id] ?? "0"),
      }));
      const res = await fetch(`/api/admin/products/${productId}/variants/bulk`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ updates }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || "Gagal menyimpan varian");

      const aggregateValue = field === "price" ? data.aggregate?.price : data.aggregate?.stock;
      if (typeof aggregateValue === "number") setValue(aggregateValue);
      setSavedAt(Date.now());
      setOpen(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan varian");
    } finally {
      setSaving(false);
    }
  }

  const isStockEmpty = field === "stock" && value === 0;
  const isStockLow = field === "stock" && value > 0 && value < 5;

  return (
    <>
      <button
        type="button"
        onClick={openEditor}
        className={`w-full rounded-lg border px-2 py-1 text-left text-sm transition ${
          savedAt
            ? "border-green-300 bg-green-50"
            : isStockEmpty
            ? "border-red-200 bg-red-50/50"
            : isStockLow
            ? "border-amber-200 bg-amber-50/50"
            : "border-transparent hover:border-zinc-200"
        }`}
        title="Klik untuk edit varian"
      >
        {field === "price" ? (
          <span className="font-medium text-zinc-950">{formatRupiah(value)}</span>
        ) : (
          <span className="inline-flex rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-bold text-zinc-700">
            {value}
          </span>
        )}
        <p className="mt-0.5 text-[10px] font-semibold text-natalo-600">
          edit varian
          {savedAt ? " ✓" : ""}
        </p>
      </button>

      {open && (
        <div
          // Modern frosted-glass: backdrop-blur halus + dim lebih ringan.
          // Konten di belakang TERLIHAT samar (blur) — bukan sekadar gelap.
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4 backdrop-blur-md"
          onClick={() => !saving && setOpen(false)}
        >
          <div
            // Dialog: solid white + ring halus + shadow-2xl elevation.
            // ring-1 ring-black/5 = depth subtle tanpa heavy shadow.
            className="w-full max-w-lg rounded-2xl bg-white p-5 shadow-2xl ring-1 ring-black/5"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h3 className="font-black text-zinc-950">
                  Edit {field === "price" ? "Harga" : "Stok"} Varian
                </h3>
                <p className="mt-1 line-clamp-1 text-sm text-zinc-500">{productName}</p>
              </div>
              <button
                type="button"
                disabled={saving}
                onClick={() => setOpen(false)}
                className="rounded-full border border-zinc-200 px-3 py-1 text-sm font-bold text-zinc-500 hover:border-zinc-400 disabled:opacity-50"
              >
                Tutup
              </button>
            </div>

            {loading ? (
              <p className="mt-6 rounded-lg bg-zinc-50 p-4 text-sm text-zinc-500">
                Memuat varian...
              </p>
            ) : variants.length === 0 ? (
              <p className="mt-6 rounded-lg bg-zinc-50 p-4 text-sm text-zinc-500">
                Varian tidak ditemukan.
              </p>
            ) : (
              <div className="mt-5 max-h-[55vh] space-y-2 overflow-y-auto pr-1">
                {variants.map((variant) => (
                  <div
                    key={variant.id}
                    className="grid grid-cols-[1fr_130px] items-center gap-3 rounded-lg border border-zinc-100 p-3"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-bold text-zinc-950">
                        {variantLabel(variant, attributes)}
                      </p>
                      {variant.sku && (
                        <p className="mt-0.5 truncate font-mono text-[11px] text-zinc-400">
                          {variant.sku}
                        </p>
                      )}
                    </div>
                    <input
                      type="text"
                      inputMode="numeric"
                      value={drafts[variant.id] ?? ""}
                      onChange={(e) => updateDraft(variant.id, e.target.value)}
                      className="rounded-lg border border-zinc-300 px-3 py-2 text-right text-sm font-semibold outline-none focus:border-zinc-950"
                    />
                  </div>
                ))}
              </div>
            )}

            {error && <p className="mt-3 text-sm font-semibold text-red-600">{error}</p>}

            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                disabled={saving}
                onClick={() => setOpen(false)}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold text-zinc-700 hover:border-zinc-500 disabled:opacity-50"
              >
                Batal
              </button>
              <button
                type="button"
                disabled={saving || loading || variants.length === 0}
                onClick={save}
                className="rounded-full bg-zinc-950 px-5 py-2 text-sm font-bold text-white hover:bg-zinc-800 disabled:opacity-50"
              >
                {saving ? "Menyimpan..." : "Simpan"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
