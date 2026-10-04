"use client";
import { useEffect, useState } from "react";
import { VariantInlineEditCell } from "./VariantInlineEditCell";

type Variant = {
  id: string;
  sku: string | null;
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
            rows.map((row) => (
              <div key={row.id} className="admin-product-variant-row">
                <div className="min-w-0 text-sm">
                  <span>
                    {attrs
                      .flatMap((attr) =>
                        attr.options
                          .filter((option) =>
                            row.options.some(
                              (ref) => ref.optionId === option.id
                            )
                          )
                          .map((option) => option.value)
                      )
                      .join(" / ") ||
                      row.sku ||
                      "Varian"}
                  </span>
                  {row.sku && (
                    <p className="mt-1 text-xs text-slate-500">{row.sku}</p>
                  )}
                  {!row.isActive && (
                    <span className="text-xs text-slate-500">Tidak aktif</span>
                  )}
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
            ))
          )}
        </div>
      </div>
    </div>
  );
}
