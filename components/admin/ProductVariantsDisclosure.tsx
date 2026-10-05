"use client";
import { useEffect, useState } from "react";
import { VariantInlineEditCell } from "./VariantInlineEditCell";

type Variant = {
  id: string;
  sku: string | null;
  imageUrl: string | null;
  price: number;
  stock: number;
  isActive: boolean;
  options: Array<{ optionId: string }>;
};
type Attribute = {
  id: string;
  name: string;
  options: Array<{ id: string; value: string }>;
};

function VariantThumbnail({ imageUrl, name }: { imageUrl: string | null; name: string }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-md border border-slate-200 bg-white p-1">
      {imageUrl && !failed ? (
        <img src={imageUrl} alt={`Foto varian ${name}`} width={48} height={48} loading="lazy" className="h-full w-full object-contain" onError={() => setFailed(true)} />
      ) : (
        <svg role="img" aria-label={`Foto varian ${name} belum tersedia`} width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-slate-300"><rect x="3" y="3" width="18" height="18" rx="3" /><circle cx="8" cy="8" r="1.5" /><path d="m3 17 5-5 4 4 4-6 5 7" /></svg>
      )}
    </div>
  );
}
export function ProductVariantsDisclosure({
  productId,
  productName,
  price,
  stock,
}: {
  productId: string;
  productName: string;
  price: number;
  stock: number;
}) {
  const [open, setOpen] = useState(false),
    [rows, setRows] = useState<Variant[]>([]),
    [attrs, setAttrs] = useState<Attribute[]>([]),
    [error, setError] = useState<string | null>(null),
    [loading, setLoading] = useState(false),
    [reload, setReload] = useState(0);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    void (async () => {
      try {
        const response = await fetch(
          `/api/admin/products/${productId}/variants`,
          { signal: controller.signal }
        );
        const data = await response.json();
        if (!response.ok)
          throw new Error(data?.error ?? "Varian gagal dimuat.");
        if (!controller.signal.aborted) {
          setRows(data.variants ?? []);
          setAttrs(data.attributes ?? []);
        }
      } catch (err) {
        if (!controller.signal.aborted)
          setError(err instanceof Error ? err.message : "Varian gagal dimuat.");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    })();
    return () => controller.abort();
  }, [open, productId, price, stock, reload]);
  return (
    <div className="admin-product-variants">
      <button
        type="button"
        aria-expanded={open}
        aria-controls={`product-variants-${productId}`}
        className="min-h-11 px-2 text-xs font-semibold text-blue-700"
        onClick={() => setOpen((value) => !value)}
      >
        {open ? "Sembunyikan variasi" : "Lihat variasi"}
        <span aria-hidden="true" className="ml-2">
          {open ? "⌃" : "⌄"}
        </span>
      </button>
      <div
        className={`admin-variant-disclosure ${open ? "is-open" : ""}`}
        aria-hidden={!open}
        inert={!open}
      >
        <div
          id={`product-variants-${productId}`}
          className="admin-variant-disclosure-content"
        >
          {loading ? (
            <p role="status" className="p-3 text-xs text-slate-500">
              Memuat variasi…
            </p>
          ) : error ? (
            <div role="alert" className="p-3 text-xs text-red-700">
              {error}{" "}
              <button
                type="button"
                className="min-h-11 underline"
                onClick={() => setReload((value) => value + 1)}
              >
                Coba lagi
              </button>
            </div>
          ) : (
            rows.map((row) => {
              const name = attrs.flatMap((attr) =>
                attr.options.filter((option) => row.options.some((ref) => ref.optionId === option.id))
                  .map((option) => option.value)
              ).join(" / ") || row.sku || "Varian";
              return (
              <div key={row.id} className="admin-product-variant-row">
                <div className="flex min-w-0 items-center gap-3 text-sm">
                  <VariantThumbnail key={row.imageUrl} imageUrl={row.imageUrl} name={name} />
                  <div className="min-w-0 break-words">
                  <span className="font-medium">{name}</span>
                  {row.sku && (
                    <p className="mt-1 text-xs text-slate-500">{row.sku}</p>
                  )}
                  {!row.isActive && (
                    <span className="text-xs text-slate-500">Tidak aktif</span>
                  )}
                  </div>
                </div>
                <VariantInlineEditCell
                  productId={productId}
                  productName={productName}
                  variantId={row.id}
                  field="price"
                  initialValue={row.price}
                />
                <VariantInlineEditCell
                  productId={productId}
                  productName={productName}
                  variantId={row.id}
                  field="stock"
                  initialValue={row.stock}
                />
              </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
