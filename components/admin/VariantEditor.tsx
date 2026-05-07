"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatRupiah } from "@/lib/format";

// ── Types ──────────────────────────────────────────────────────
type OptionDraft = {
  tempId: string;
  value: string;
};

type AttrDraft = {
  tempId: string;
  name: string;
  options: OptionDraft[];
  inputVal: string; // untuk input tambah opsi
};

type VariantRow = {
  tempId: string;
  /** ["0:800GR", "1:Beef"] — format optionRef */
  optionRefs: string[];
  /** display: ["800GR", "Beef"] */
  optionValues: string[];
  price: string;
  stock: string;
  weightGram: string;
  sku: string;
  imageUrl: string;
  isActive: boolean;
};

let _counter = 0;
const uid = () => `t${++_counter}`;

function cartesian<T>(arrays: T[][]): T[][] {
  if (arrays.length === 0) return [[]];
  const [first, ...rest] = arrays;
  const restProduct = cartesian(rest);
  return first.flatMap((item) => restProduct.map((r) => [item, ...r]));
}

// ── Props ──────────────────────────────────────────────────────
interface Props {
  productId: string;
  initialHasVariants: boolean;
  initialAttributes: Array<{
    id: string;
    name: string;
    position: number;
    options: Array<{ id: string; value: string; position: number }>;
  }>;
  initialVariants: Array<{
    id: string;
    price: number;
    stock: number;
    weightGram: number;
    sku: string | null;
    imageUrl: string | null;
    isActive: boolean;
    options: Array<{ optionId: string }>;
  }>;
}

export function VariantEditor({
  productId,
  initialHasVariants,
  initialAttributes,
  initialVariants,
}: Props) {
  const [hasVariants, setHasVariants] = useState(initialHasVariants);
  const [attrs, setAttrs] = useState<AttrDraft[]>(() =>
    initialAttributes
      .sort((a, b) => a.position - b.position)
      .map((a) => ({
        tempId: uid(),
        name: a.name,
        inputVal: "",
        options: a.options
          .sort((x, y) => x.position - y.position)
          .map((o) => ({ tempId: uid(), value: o.value })),
      }))
  );
  const [rows, setRows] = useState<VariantRow[]>([]);
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [bulkPrice, setBulkPrice] = useState("");
  const [bulkStock, setBulkStock] = useState("");
  const [bulkWeight, setBulkWeight] = useState("");

  // ── Build variant rows dari cartesian product ─────────────────
  const buildRows = useCallback(
    (currentAttrs: AttrDraft[], preservedRows: VariantRow[]): VariantRow[] => {
      if (currentAttrs.length === 0) return [];
      const optionArrays = currentAttrs.map((a) =>
        a.options.map((o, idx) => ({
          tempId: o.tempId,
          value: o.value,
          attrIdx: currentAttrs.indexOf(a),
        }))
      );
      if (optionArrays.some((arr) => arr.length === 0)) return [];

      const combos = cartesian(optionArrays);

      return combos.map((combo) => {
        const optionRefs = combo.map((o) => `${o.attrIdx}:${o.value}`);
        const optionValues = combo.map((o) => o.value);
        const key = optionRefs.join("|");

        // Preserve existing row data
        const existing = preservedRows.find(
          (r) => r.optionRefs.join("|") === key
        );

        return {
          tempId: existing?.tempId ?? uid(),
          optionRefs,
          optionValues,
          price: existing?.price ?? "",
          stock: existing?.stock ?? "0",
          weightGram: existing?.weightGram ?? "500",
          sku: existing?.sku ?? "",
          imageUrl: existing?.imageUrl ?? "",
          isActive: existing?.isActive ?? true,
        };
      });
    },
    []
  );

  // Inisialisasi rows dari data existing
  useEffect(() => {
    if (!initialHasVariants || initialAttributes.length === 0) return;

    // Build initial rows dari initialVariants
    const initRows: VariantRow[] = [];
    const attrDrafts = initialAttributes
      .sort((a, b) => a.position - b.position)
      .map((a) => ({
        tempId: uid(),
        name: a.name,
        inputVal: "",
        options: a.options
          .sort((x, y) => x.position - y.position)
          .map((o) => ({ tempId: uid(), value: o.value })),
      }));

    // Map optionId → {attrIdx, value}
    const optionMap = new Map<string, { attrIdx: number; value: string }>();
    initialAttributes.forEach((a, idx) => {
      a.options.forEach((o) => optionMap.set(o.id, { attrIdx: idx, value: o.value }));
    });

    for (const v of initialVariants) {
      const optionRefs = v.options
        .map((o) => {
          const info = optionMap.get(o.optionId);
          return info ? `${info.attrIdx}:${info.value}` : null;
        })
        .filter((x): x is string => !!x)
        .sort();

      const optionValues = v.options
        .map((o) => optionMap.get(o.optionId)?.value ?? "")
        .filter(Boolean);

      initRows.push({
        tempId: uid(),
        optionRefs,
        optionValues,
        price: String(v.price),
        stock: String(v.stock),
        weightGram: String(v.weightGram),
        sku: v.sku ?? "",
        imageUrl: v.imageUrl ?? "",
        isActive: v.isActive,
      });
    }

    setRows(buildRows(attrDrafts, initRows));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Regenerate rows saat attrs berubah
  const prevAttrsRef = useRef(attrs);
  useEffect(() => {
    if (prevAttrsRef.current === attrs) return;
    prevAttrsRef.current = attrs;
    setRows((prev) => buildRows(attrs, prev));
  }, [attrs, buildRows]);

  // ── Attr handlers ─────────────────────────────────────────────
  function addAttr() {
    if (attrs.length >= 3) return;
    setAttrs((prev) => [
      ...prev,
      { tempId: uid(), name: "", options: [], inputVal: "" },
    ]);
  }

  function updateAttrName(tempId: string, name: string) {
    setAttrs((prev) =>
      prev.map((a) => (a.tempId === tempId ? { ...a, name } : a))
    );
  }

  function removeAttr(tempId: string) {
    setAttrs((prev) => prev.filter((a) => a.tempId !== tempId));
  }

  function addOption(attrTempId: string, value: string) {
    if (!value.trim()) return;
    setAttrs((prev) =>
      prev.map((a) =>
        a.tempId === attrTempId
          ? {
              ...a,
              options: [...a.options, { tempId: uid(), value: value.trim() }],
              inputVal: "",
            }
          : a
      )
    );
  }

  function removeOption(attrTempId: string, optTempId: string) {
    setAttrs((prev) =>
      prev.map((a) =>
        a.tempId === attrTempId
          ? { ...a, options: a.options.filter((o) => o.tempId !== optTempId) }
          : a
      )
    );
  }

  function updateAttrInput(attrTempId: string, val: string) {
    setAttrs((prev) =>
      prev.map((a) => (a.tempId === attrTempId ? { ...a, inputVal: val } : a))
    );
  }

  // ── Row handlers ──────────────────────────────────────────────
  function updateRow(tempId: string, field: keyof VariantRow, value: string | boolean) {
    setRows((prev) =>
      prev.map((r) => (r.tempId === tempId ? { ...r, [field]: value } : r))
    );
  }

  function applyBulk() {
    setRows((prev) =>
      prev.map((r) => ({
        ...r,
        ...(bulkPrice ? { price: bulkPrice } : {}),
        ...(bulkStock ? { stock: bulkStock } : {}),
        ...(bulkWeight ? { weightGram: bulkWeight } : {}),
      }))
    );
    setBulkPrice("");
    setBulkStock("");
    setBulkWeight("");
  }

  // ── Validasi ──────────────────────────────────────────────────
  const validationErrors = useMemo(() => {
    const errs: string[] = [];
    if (!hasVariants) return errs;
    if (attrs.some((a) => !a.name.trim())) errs.push("Semua atribut harus punya nama.");
    if (attrs.some((a) => a.options.length === 0))
      errs.push("Setiap atribut harus punya minimal 1 opsi.");
    if (rows.length === 0) errs.push("Tambah minimal 1 opsi ke setiap atribut.");
    const activeRows = rows.filter((r) => r.isActive);
    if (activeRows.length === 0) errs.push("Minimal 1 varian harus aktif.");
    if (rows.some((r) => r.isActive && (!r.price || Number(r.price) <= 0)))
      errs.push("Semua varian aktif harus punya harga > 0.");
    // SKU uniqueness (frontend check)
    const skus = rows.filter((r) => r.sku).map((r) => r.sku);
    if (skus.length !== new Set(skus).size) errs.push("SKU harus unik.");
    return errs;
  }, [hasVariants, attrs, rows]);

  // ── Save ──────────────────────────────────────────────────────
  async function handleSave() {
    if (validationErrors.length > 0) return;
    setSaving(true);
    setSaveMsg(null);
    try {
      const payload = {
        hasVariants,
        attributes: attrs.map((a, idx) => ({
          name: a.name,
          position: idx,
          options: a.options.map((o, oIdx) => ({
            value: o.value,
            position: oIdx,
          })),
        })),
        variants: rows.map((r) => ({
          optionRefs: r.optionRefs,
          price: Number(r.price) || 0,
          stock: Number(r.stock) || 0,
          weightGram: Number(r.weightGram) || 500,
          sku: r.sku || undefined,
          imageUrl: r.imageUrl || undefined,
          isActive: r.isActive,
        })),
      };

      const res = await fetch(`/api/admin/products/${productId}/variants`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal menyimpan");
      setSaveMsg({ ok: true, text: "Varian berhasil disimpan!" });
    } catch (e) {
      setSaveMsg({ ok: false, text: e instanceof Error ? e.message : "Gagal menyimpan varian." });
    } finally {
      setSaving(false);
    }
  }

  // ── Render ────────────────────────────────────────────────────
  return (
    <div className="mt-8 rounded-2xl border border-zinc-200 bg-white p-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-black text-zinc-950">Varian Produk</h2>
          <p className="mt-0.5 text-sm text-zinc-500">
            Aktifkan jika produk ini punya pilihan seperti ukuran, berat, atau warna.
          </p>
        </div>
        {/* Toggle */}
        <button
          type="button"
          onClick={() => {
            setHasVariants((v) => !v);
            setSaveMsg(null);
          }}
          className={`relative flex h-7 w-12 shrink-0 items-center rounded-full transition-colors ${
            hasVariants ? "bg-natalo-600" : "bg-zinc-300"
          }`}
        >
          <span
            className={`absolute h-5 w-5 rounded-full bg-white shadow transition-transform ${
              hasVariants ? "translate-x-6" : "translate-x-1"
            }`}
          />
        </button>
      </div>

      {hasVariants && (
        <div className="mt-6 space-y-6">
          {/* ── Attribute builder ────────────────────────────── */}
          <div className="space-y-4">
            {attrs.map((attr, attrIdx) => (
              <div
                key={attr.tempId}
                className="rounded-xl border border-zinc-200 bg-zinc-50 p-4"
              >
                <div className="flex items-center gap-3">
                  <span className="text-xs font-bold text-zinc-400">
                    Atribut {attrIdx + 1}
                  </span>
                  <input
                    type="text"
                    value={attr.name}
                    onChange={(e) => updateAttrName(attr.tempId, e.target.value)}
                    placeholder='misal "Berat", "Rasa", "Warna"'
                    className="flex-1 rounded-lg border border-zinc-300 px-3 py-1.5 text-sm outline-none focus:border-zinc-950"
                  />
                  <button
                    type="button"
                    onClick={() => removeAttr(attr.tempId)}
                    className="text-sm text-zinc-400 hover:text-red-500"
                  >
                    Hapus
                  </button>
                </div>

                {/* Options */}
                <div className="mt-3 flex flex-wrap items-center gap-2">
                  {attr.options.map((opt) => (
                    <span
                      key={opt.tempId}
                      className="flex items-center gap-1 rounded-lg border border-zinc-200 bg-white px-3 py-1 text-sm font-medium"
                    >
                      {opt.value}
                      <button
                        type="button"
                        onClick={() => removeOption(attr.tempId, opt.tempId)}
                        className="ml-1 text-zinc-300 hover:text-red-400"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                  {/* Input tambah opsi */}
                  <input
                    type="text"
                    value={attr.inputVal}
                    onChange={(e) => updateAttrInput(attr.tempId, e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        addOption(attr.tempId, attr.inputVal);
                      }
                    }}
                    placeholder="Tambah opsi, tekan Enter"
                    className="min-w-[160px] flex-1 rounded-lg border border-dashed border-zinc-300 px-3 py-1 text-sm outline-none focus:border-zinc-950"
                  />
                  <button
                    type="button"
                    onClick={() => addOption(attr.tempId, attr.inputVal)}
                    className="rounded-lg border border-zinc-300 px-3 py-1 text-xs font-bold hover:bg-zinc-100"
                  >
                    + Tambah
                  </button>
                </div>
              </div>
            ))}

            {attrs.length < 3 && (
              <button
                type="button"
                onClick={addAttr}
                className="rounded-xl border border-dashed border-zinc-300 px-4 py-3 text-sm font-semibold text-zinc-500 hover:border-zinc-500 hover:text-zinc-950"
              >
                + Tambah Atribut {attrs.length === 0 ? "" : `#${attrs.length + 1}`}
              </button>
            )}
          </div>

          {/* ── Tabel kombinasi ──────────────────────────────── */}
          {rows.length > 0 && (
            <div>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h3 className="text-sm font-bold text-zinc-700">
                  Tabel Kombinasi ({rows.length} varian)
                </h3>
                {/* Bulk fill */}
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-xs text-zinc-400">Isi semua:</span>
                  <input
                    type="number"
                    value={bulkPrice}
                    onChange={(e) => setBulkPrice(e.target.value)}
                    placeholder="Harga"
                    className="w-24 rounded-lg border border-zinc-300 px-2 py-1 text-xs outline-none focus:border-zinc-950"
                  />
                  <input
                    type="number"
                    value={bulkStock}
                    onChange={(e) => setBulkStock(e.target.value)}
                    placeholder="Stok"
                    className="w-20 rounded-lg border border-zinc-300 px-2 py-1 text-xs outline-none focus:border-zinc-950"
                  />
                  <input
                    type="number"
                    value={bulkWeight}
                    onChange={(e) => setBulkWeight(e.target.value)}
                    placeholder="Gram"
                    className="w-20 rounded-lg border border-zinc-300 px-2 py-1 text-xs outline-none focus:border-zinc-950"
                  />
                  <button
                    type="button"
                    onClick={applyBulk}
                    className="rounded-lg bg-zinc-950 px-3 py-1 text-xs font-bold text-white hover:bg-zinc-700"
                  >
                    Apply
                  </button>
                </div>
              </div>

              <div className="mt-3 overflow-x-auto rounded-xl border border-zinc-200">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-50 text-xs font-bold uppercase tracking-wide text-zinc-400">
                    <tr>
                      {attrs.map((a) => (
                        <th key={a.tempId} className="px-3 py-3 text-left">
                          {a.name || `Atribut ${attrs.indexOf(a) + 1}`}
                        </th>
                      ))}
                      <th className="px-3 py-3 text-left">Harga (Rp) *</th>
                      <th className="px-3 py-3 text-left">Stok</th>
                      <th className="px-3 py-3 text-left">Gram</th>
                      <th className="px-3 py-3 text-left">SKU</th>
                      <th className="px-3 py-3 text-center">Aktif</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-100">
                    {rows.map((row) => (
                      <tr
                        key={row.tempId}
                        className={row.isActive ? "bg-white" : "bg-zinc-50 opacity-60"}
                      >
                        {/* Option value cells */}
                        {row.optionValues.map((val, i) => (
                          <td key={i} className="px-3 py-3">
                            <span className="rounded-lg bg-natalo-50 px-2 py-1 text-xs font-semibold text-natalo-700">
                              {val}
                            </span>
                          </td>
                        ))}

                        {/* Harga */}
                        <td className="px-3 py-3">
                          <input
                            type="number"
                            value={row.price}
                            onChange={(e) => updateRow(row.tempId, "price", e.target.value)}
                            placeholder="0"
                            min={0}
                            className="w-28 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-zinc-950"
                          />
                          {row.price && Number(row.price) > 0 && (
                            <p className="mt-0.5 text-[10px] text-zinc-400">
                              {formatRupiah(Number(row.price))}
                            </p>
                          )}
                        </td>

                        {/* Stok */}
                        <td className="px-3 py-3">
                          <input
                            type="number"
                            value={row.stock}
                            onChange={(e) => updateRow(row.tempId, "stock", e.target.value)}
                            min={0}
                            className="w-20 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-zinc-950"
                          />
                        </td>

                        {/* Gram */}
                        <td className="px-3 py-3">
                          <input
                            type="number"
                            value={row.weightGram}
                            onChange={(e) => updateRow(row.tempId, "weightGram", e.target.value)}
                            min={1}
                            className="w-20 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-zinc-950"
                          />
                        </td>

                        {/* SKU */}
                        <td className="px-3 py-3">
                          <input
                            type="text"
                            value={row.sku}
                            onChange={(e) => updateRow(row.tempId, "sku", e.target.value.toUpperCase())}
                            placeholder="opsional"
                            className="w-28 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-zinc-950"
                          />
                        </td>

                        {/* Aktif toggle */}
                        <td className="px-3 py-3 text-center">
                          <button
                            type="button"
                            onClick={() => updateRow(row.tempId, "isActive", !row.isActive)}
                            className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
                              row.isActive ? "bg-green-500" : "bg-zinc-300"
                            }`}
                          >
                            <span
                              className={`absolute h-3.5 w-3.5 rounded-full bg-white shadow transition-transform ${
                                row.isActive ? "translate-x-4" : "translate-x-1"
                              }`}
                            />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Validasi errors */}
          {validationErrors.length > 0 && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4">
              <p className="text-sm font-semibold text-red-600">Perlu diperbaiki:</p>
              <ul className="mt-2 space-y-1">
                {validationErrors.map((e, i) => (
                  <li key={i} className="text-sm text-red-500">
                    • {e}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}

      {/* Save button */}
      <div className="mt-6 flex items-center gap-4">
        <button
          type="button"
          onClick={handleSave}
          disabled={saving || (hasVariants && validationErrors.length > 0)}
          className="rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {saving ? "Menyimpan..." : "Simpan Varian"}
        </button>

        {saveMsg && (
          <p
            className={`text-sm font-semibold ${
              saveMsg.ok ? "text-green-600" : "text-red-500"
            }`}
          >
            {saveMsg.ok ? "✓ " : "✗ "}
            {saveMsg.text}
          </p>
        )}
      </div>
    </div>
  );
}
