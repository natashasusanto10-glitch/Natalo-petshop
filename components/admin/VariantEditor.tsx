"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatRupiah } from "@/lib/format";

// ── Types ──────────────────────────────────────────────────────
type OptionDraft = {
  tempId: string;
  /** Nilai opsi yang admin ketik (mis. "Chicken", "Beef"). Boleh kosong
   *  sementara — opsi kosong di-filter saat generate tabel kombinasi
   *  + saat save. Empty trailing slot di-handle otomatis: selalu ada
   *  1 row kosong di akhir sebagai "add affordance". */
  value: string;
};

type AttrDraft = {
  tempId: string;
  /** Nama atribut (mis. "Warna", "Rasa", "Ukuran"). Header kolom tabel
   *  kombinasi pakai value ini secara live. */
  name: string;
  options: OptionDraft[];
};

type VariantRow = {
  tempId: string;
  /** ["0:Chicken", "1:1KG"] — format optionRef untuk preserve identity */
  optionRefs: string[];
  /** display: ["Chicken", "1KG"] */
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
/**
 * Payload yang di-emit ke parent saat draft mode (onChange). Match
 * struktur backend POST /api/admin/products & PUT variants endpoint.
 */
export type VariantEditorDraftPayload = {
  hasVariants: boolean;
  attributes: Array<{
    name: string;
    position: number;
    options: Array<{ value: string; position: number }>;
  }>;
  variants: Array<{
    optionRefs: string[];
    price: number;
    stock: number;
    weightGram: number;
    sku?: string;
    imageUrl?: string;
    isActive: boolean;
  }>;
};

interface Props {
  /** Required di standalone mode (call API sendiri). Optional di draft
   *  mode (parent yang submit). */
  productId?: string;
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
  /**
   * Draft mode: callback yang dipanggil tiap state berubah. Kalau
   * provided, component TIDAK call API saat save; parent yang
   * collect data + submit bersama form lain. Juga auto-hide tombol
   * "Simpan Varian" standalone.
   */
  onChange?: (payload: VariantEditorDraftPayload) => void;
}

export function VariantEditor({
  productId,
  initialHasVariants,
  initialAttributes,
  initialVariants,
  onChange,
}: Props) {
  const isDraftMode = typeof onChange === "function";
  const [hasVariants, setHasVariants] = useState(initialHasVariants);
  const [attrs, setAttrs] = useState<AttrDraft[]>(() =>
    initialAttributes
      .sort((a, b) => a.position - b.position)
      .map((a) => ({
        tempId: uid(),
        name: a.name,
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
  const [bulkSku, setBulkSku] = useState("");
  const [bulkWeight, setBulkWeight] = useState("");
  /** Submit attempted at least once — controls when to show inline field errors. */
  const [showFieldErrors, setShowFieldErrors] = useState(false);

  // Filter opsi kosong sebelum generate kombinasi — empty trailing slot
  // jangan ikut ke tabel.
  const nonEmptyAttrs = useMemo(
    () =>
      attrs
        .map((a) => ({
          ...a,
          options: a.options.filter((o) => o.value.trim().length > 0),
        }))
        .filter((a) => a.options.length > 0 && a.name.trim().length > 0),
    [attrs]
  );

  // ── Build variant rows dari cartesian product ─────────────────
  const buildRows = useCallback(
    (currentAttrs: AttrDraft[], preservedRows: VariantRow[]): VariantRow[] => {
      if (currentAttrs.length === 0) return [];
      const optionArrays = currentAttrs.map((a, attrIdx) =>
        a.options.map((o) => ({
          tempId: o.tempId,
          value: o.value,
          attrIdx,
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

    const initRows: VariantRow[] = [];

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

    setRows(buildRows(nonEmptyAttrs, initRows));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Regenerate rows saat attrs berubah (filtered). Live sync — tiap
  // keystroke di opsi langsung update tabel di bawah.
  const prevAttrsKeyRef = useRef("");
  useEffect(() => {
    // Key = serialisasi attrs ringkas. Re-run hanya kalau struktur
    // (jumlah/value opsi) berubah, bukan tiap render.
    const key = nonEmptyAttrs
      .map((a) => `${a.name}|${a.options.map((o) => o.value).join(",")}`)
      .join("||");
    if (prevAttrsKeyRef.current === key) return;
    prevAttrsKeyRef.current = key;
    setRows((prev) => buildRows(nonEmptyAttrs, prev));
  }, [nonEmptyAttrs, buildRows]);

  // Draft mode: emit ke parent tiap kali state berubah, supaya parent
  // form bisa submit semuanya bersama. Pakai useEffect dengan deps state
  // utama untuk auto-fire saat berubah.
  useEffect(() => {
    if (!onChange) return;
    onChange({
      hasVariants,
      attributes: nonEmptyAttrs.map((a, idx) => ({
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
    });
  }, [hasVariants, nonEmptyAttrs, rows, onChange]);

  // Auto-maintain trailing empty slot: setiap atribut harus selalu punya
  // 1 input kosong di akhir sebagai "add affordance". Begitu admin ketik
  // di slot kosong itu, append 1 slot kosong baru.
  useEffect(() => {
    setAttrs((prev) => {
      let changed = false;
      const next = prev.map((a) => {
        const last = a.options[a.options.length - 1];
        if (!last || last.value.trim().length > 0) {
          // Last option non-empty (atau attr baru tanpa option sama
          // sekali) → tambah empty slot.
          changed = true;
          return {
            ...a,
            options: [...a.options, { tempId: uid(), value: "" }],
          };
        }
        return a;
      });
      return changed ? next : prev;
    });
  }, [attrs]);

  // ── Attr handlers ─────────────────────────────────────────────
  function addAttr() {
    if (attrs.length >= 3) return;
    setAttrs((prev) => [
      ...prev,
      // Init dengan 1 empty slot — useEffect di atas tidak akan
      // re-trigger karena last sudah empty.
      {
        tempId: uid(),
        name: "",
        options: [{ tempId: uid(), value: "" }],
      },
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

  /** Direct edit option value — Shopee-style form-row-based (bukan chip
   *  yang harus dikonfirmasi via Enter). */
  function updateOptionValue(attrTempId: string, optTempId: string, value: string) {
    setAttrs((prev) =>
      prev.map((a) =>
        a.tempId === attrTempId
          ? {
              ...a,
              options: a.options.map((o) =>
                o.tempId === optTempId ? { ...o, value } : o
              ),
            }
          : a
      )
    );
  }

  function removeOption(attrTempId: string, optTempId: string) {
    setAttrs((prev) =>
      prev.map((a) => {
        if (a.tempId !== attrTempId) return a;
        const remaining = a.options.filter((o) => o.tempId !== optTempId);
        // Pastikan tetap ada minimal 1 row (yang nanti otomatis jadi
        // empty slot lagi via useEffect kalau dia non-empty terhapus).
        if (remaining.length === 0) {
          return { ...a, options: [{ tempId: uid(), value: "" }] };
        }
        return { ...a, options: remaining };
      })
    );
  }

  /** Insert empty option row tepat setelah row yang diberi tag. Dipanggil
   *  saat admin klik [+] di samping suatu opsi. */
  function insertOptionAfter(attrTempId: string, afterOptTempId: string) {
    setAttrs((prev) =>
      prev.map((a) => {
        if (a.tempId !== attrTempId) return a;
        const idx = a.options.findIndex((o) => o.tempId === afterOptTempId);
        if (idx < 0) return a;
        const next = [...a.options];
        next.splice(idx + 1, 0, { tempId: uid(), value: "" });
        return { ...a, options: next };
      })
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
        ...(bulkSku ? { sku: bulkSku } : {}),
        ...(bulkWeight ? { weightGram: bulkWeight } : {}),
      }))
    );
    setBulkPrice("");
    setBulkStock("");
    setBulkSku("");
    setBulkWeight("");
  }

  // ── Validasi ──────────────────────────────────────────────────
  const validationErrors = useMemo(() => {
    const errs: string[] = [];
    if (!hasVariants) return errs;
    if (attrs.some((a) => !a.name.trim()))
      errs.push("Semua atribut harus punya nama.");
    if (nonEmptyAttrs.length === 0)
      errs.push("Tambah minimal 1 atribut dengan opsi terisi.");
    if (rows.length === 0)
      errs.push("Tambah minimal 1 opsi ke setiap atribut.");
    const activeRows = rows.filter((r) => r.isActive);
    if (activeRows.length === 0) errs.push("Minimal 1 varian harus aktif.");
    if (rows.some((r) => r.isActive && (!r.price || Number(r.price) <= 0)))
      errs.push("Semua varian aktif harus punya harga > 0.");
    // SKU uniqueness (frontend check)
    const skus = rows.filter((r) => r.sku.trim()).map((r) => r.sku.trim());
    if (skus.length !== new Set(skus).size) errs.push("Kode SKU harus unik.");
    return errs;
  }, [hasVariants, attrs, nonEmptyAttrs, rows]);

  /** Cek apakah satu input opsi kosong yang BUKAN trailing slot (yang
   *  diharapkan kosong). Dipakai untuk inline error "Kolom wajib diisi". */
  function isOptionRequiredEmpty(attr: AttrDraft, opt: OptionDraft): boolean {
    const idx = attr.options.findIndex((o) => o.tempId === opt.tempId);
    const isTrailing = idx === attr.options.length - 1;
    return !isTrailing && opt.value.trim().length === 0;
  }

  // ── Save ──────────────────────────────────────────────────────
  async function handleSave() {
    setShowFieldErrors(true);
    if (validationErrors.length > 0) return;
    setSaving(true);
    setSaveMsg(null);
    try {
      const payload = {
        hasVariants,
        attributes: nonEmptyAttrs.map((a, idx) => ({
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
      setShowFieldErrors(false);
    } catch (e) {
      setSaveMsg({
        ok: false,
        text:
          e instanceof Error
            ? e.message
            : "Gagal menyimpan karena terdapat kesalahan, edit dahulu dan coba lagi.",
      });
    } finally {
      setSaving(false);
    }
  }

  // ── Render ────────────────────────────────────────────────────
  return (
    <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-4 md:mt-8 md:p-6">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-base font-black text-zinc-950 md:text-lg">
            <span className="mr-1 text-red-500">•</span>Variasi
          </h2>
          <p className="mt-0.5 text-xs text-zinc-500 md:text-sm">
            Aktifkan jika produk ini punya pilihan seperti rasa, warna, atau ukuran.
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

      {!hasVariants && (
        // Aktifkan affordance — mirip Shopee yang punya "+ Aktifkan Variasi"
        // saat varian belum on. Kalau hasVariants true, dia auto-render
        // builder di bawah; toggle di header tetap tersedia untuk off.
        <button
          type="button"
          onClick={() => {
            setHasVariants(true);
            if (attrs.length === 0) addAttr();
          }}
          className="mt-4 inline-flex items-center gap-2 rounded-lg border border-dashed border-natalo-300 px-4 py-2 text-sm font-bold text-natalo-700 hover:border-natalo-500 hover:bg-natalo-50"
        >
          + Aktifkan Variasi
        </button>
      )}

      {hasVariants && (
        <div className="mt-6 space-y-6">
          {/* ── Attribute builder (Shopee-style form-row-based) ────── */}
          <div className="space-y-4">
            {attrs.map((attr, attrIdx) => (
              <div
                key={attr.tempId}
                className="rounded-xl border border-zinc-200 bg-zinc-50/60 p-4"
              >
                {/* Header: "Variasi N" + close × */}
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-semibold text-zinc-600">
                      Variasi{attrs.length > 1 ? ` ${attrIdx + 1}` : ""}
                    </p>
                    <input
                      type="text"
                      value={attr.name}
                      onChange={(e) => updateAttrName(attr.tempId, e.target.value)}
                      placeholder='Cth. Warna, Rasa, Ukuran'
                      className={`mt-2 w-full rounded-lg border bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600 ${
                        showFieldErrors && !attr.name.trim()
                          ? "border-red-400"
                          : "border-zinc-300"
                      }`}
                    />
                    {showFieldErrors && !attr.name.trim() && (
                      <p className="mt-1 text-xs text-red-500">
                        Kolom wajib diisi
                      </p>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => removeAttr(attr.tempId)}
                    className="rounded-full p-1 text-zinc-400 hover:bg-white hover:text-red-500"
                    title="Hapus variasi"
                  >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <line x1="18" y1="6" x2="6" y2="18" />
                      <line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                  </button>
                </div>

                {/* Opsi grid (2-col desktop, 1-col mobile) */}
                <div className="mt-4">
                  <p className="text-sm font-semibold text-zinc-600">
                    <span className="mr-1 text-red-500">•</span>Opsi
                  </p>
                  <div className="mt-2 grid gap-2 sm:grid-cols-2">
                    {attr.options.map((opt, optIdx) => {
                      const isTrailing = optIdx === attr.options.length - 1;
                      const showError =
                        showFieldErrors && isOptionRequiredEmpty(attr, opt);
                      return (
                        <div key={opt.tempId} className="flex items-start gap-1.5">
                          <div className="flex-1">
                            <input
                              type="text"
                              value={opt.value}
                              onChange={(e) =>
                                updateOptionValue(attr.tempId, opt.tempId, e.target.value)
                              }
                              placeholder={isTrailing ? "Masukkan" : "Cth. Merah, dll"}
                              className={`w-full rounded-lg border bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600 ${
                                showError ? "border-red-400" : "border-zinc-300"
                              }`}
                            />
                            {showError && (
                              <p className="mt-1 text-xs text-red-500">
                                Kolom wajib diisi
                              </p>
                            )}
                          </div>
                          <button
                            type="button"
                            onClick={() =>
                              insertOptionAfter(attr.tempId, opt.tempId)
                            }
                            className="shrink-0 rounded p-2 text-zinc-400 hover:bg-white hover:text-natalo-600"
                            title="Tambah opsi di bawah"
                          >
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                              <line x1="12" y1="5" x2="12" y2="19" />
                              <line x1="5" y1="12" x2="19" y2="12" />
                            </svg>
                          </button>
                          <button
                            type="button"
                            onClick={() => removeOption(attr.tempId, opt.tempId)}
                            disabled={attr.options.length <= 1}
                            className="shrink-0 rounded p-2 text-zinc-400 hover:bg-white hover:text-red-500 disabled:cursor-not-allowed disabled:opacity-30"
                            title="Hapus opsi"
                          >
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                              <polyline points="3 6 5 6 21 6" />
                              <path d="M19 6l-1.5 14a2 2 0 0 1-2 2H8.5a2 2 0 0 1-2-2L5 6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                            </svg>
                          </button>
                        </div>
                      );
                    })}
                  </div>
                </div>
              </div>
            ))}

            {attrs.length < 3 && (
              <button
                type="button"
                onClick={addAttr}
                className="w-full rounded-xl border border-dashed border-natalo-300 px-4 py-3 text-sm font-semibold text-natalo-700 hover:border-natalo-500 hover:bg-natalo-50"
              >
                + Tambah Variasi {attrs.length + 1}
              </button>
            )}
          </div>

          {/* ── Daftar Variasi (live preview tabel) ───────────────── */}
          {rows.length > 0 && (
            <div>
              <h3 className="text-sm font-bold text-zinc-700">Daftar Variasi</h3>

              {/* Quick fill row */}
              <div className="mt-2 flex flex-wrap items-center gap-2 rounded-xl border border-zinc-200 bg-zinc-50/60 p-3">
                <div className="grid w-full grid-cols-2 gap-2 sm:flex sm:flex-1 sm:flex-wrap">
                  <div className="relative">
                    <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
                      Rp
                    </span>
                    <input
                      type="number"
                      value={bulkPrice}
                      onChange={(e) => setBulkPrice(e.target.value)}
                      placeholder="Harga"
                      className="w-full rounded-lg border border-zinc-300 bg-white pl-8 pr-3 py-2 text-sm outline-none focus:border-natalo-600 sm:w-32"
                    />
                  </div>
                  <input
                    type="number"
                    value={bulkStock}
                    onChange={(e) => setBulkStock(e.target.value)}
                    placeholder="Stok"
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600 sm:w-24"
                  />
                  <input
                    type="text"
                    value={bulkSku}
                    onChange={(e) => setBulkSku(e.target.value.toUpperCase())}
                    placeholder="Kode SKU"
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600 sm:w-32"
                  />
                  <input
                    type="number"
                    value={bulkWeight}
                    onChange={(e) => setBulkWeight(e.target.value)}
                    placeholder="Berat (gram)"
                    className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600 sm:w-32"
                  />
                </div>
                <button
                  type="button"
                  onClick={applyBulk}
                  className="w-full shrink-0 rounded-lg bg-natalo-600 px-4 py-2 text-sm font-bold text-white hover:bg-natalo-700 sm:w-auto"
                >
                  Terapkan Ke Semua
                </button>
              </div>

              {/* Mobile card list */}
              <div className="mt-3 space-y-3 md:hidden">
                {rows.map((row) => (
                  <div
                    key={row.tempId}
                    className={`rounded-xl border p-3 ${
                      row.isActive
                        ? "border-zinc-200 bg-white"
                        : "border-zinc-200 bg-zinc-50 opacity-70"
                    }`}
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex flex-wrap gap-1.5">
                        {row.optionValues.map((val, i) => (
                          <span
                            key={i}
                            className="rounded-md bg-natalo-50 px-2 py-0.5 text-[11px] font-bold text-natalo-700"
                          >
                            {nonEmptyAttrs[i]?.name
                              ? `${nonEmptyAttrs[i].name}: `
                              : ""}
                            {val}
                          </span>
                        ))}
                      </div>
                      <button
                        type="button"
                        onClick={() =>
                          updateRow(row.tempId, "isActive", !row.isActive)
                        }
                        className={`inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-[11px] font-bold transition-colors ${
                          row.isActive
                            ? "bg-green-50 text-green-700"
                            : "bg-zinc-100 text-zinc-500"
                        }`}
                      >
                        <span
                          className={`relative inline-flex h-4 w-7 items-center rounded-full transition-colors ${
                            row.isActive ? "bg-green-500" : "bg-zinc-300"
                          }`}
                        >
                          <span
                            className={`absolute h-3 w-3 rounded-full bg-white shadow transition-transform ${
                              row.isActive ? "translate-x-3.5" : "translate-x-0.5"
                            }`}
                          />
                        </span>
                        {row.isActive ? "Aktif" : "Nonaktif"}
                      </button>
                    </div>

                    {/* Image upload */}
                    <div className="mt-3">
                      <VariantImageCell
                        imageUrl={row.imageUrl}
                        onChange={(url) => updateRow(row.tempId, "imageUrl", url)}
                      />
                    </div>

                    <div className="mt-3 grid grid-cols-2 gap-2.5">
                      <label className="block">
                        <span className="text-[10px] font-bold uppercase tracking-wide text-zinc-400">
                          <span className="mr-0.5 text-red-500">*</span>Harga
                        </span>
                        <input
                          type="number"
                          value={row.price}
                          onChange={(e) =>
                            updateRow(row.tempId, "price", e.target.value)
                          }
                          placeholder="0"
                          min={0}
                          inputMode="numeric"
                          className={`mt-0.5 w-full rounded-lg border px-2.5 py-2 text-sm outline-none focus:border-natalo-600 ${
                            showFieldErrors && row.isActive && (!row.price || Number(row.price) <= 0)
                              ? "border-red-400"
                              : "border-zinc-300"
                          }`}
                        />
                        {row.price && Number(row.price) > 0 && (
                          <p className="mt-0.5 text-[10px] text-zinc-400">
                            {formatRupiah(Number(row.price))}
                          </p>
                        )}
                      </label>
                      <label className="block">
                        <span className="text-[10px] font-bold uppercase tracking-wide text-zinc-400">
                          <span className="mr-0.5 text-red-500">*</span>Stok
                        </span>
                        <input
                          type="number"
                          value={row.stock}
                          onChange={(e) =>
                            updateRow(row.tempId, "stock", e.target.value)
                          }
                          min={0}
                          inputMode="numeric"
                          className="mt-0.5 w-full rounded-lg border border-zinc-300 px-2.5 py-2 text-sm outline-none focus:border-natalo-600"
                        />
                      </label>
                      <label className="block">
                        <span className="text-[10px] font-bold uppercase tracking-wide text-zinc-400">
                          Kode SKU
                        </span>
                        <input
                          type="text"
                          value={row.sku}
                          onChange={(e) =>
                            updateRow(row.tempId, "sku", e.target.value.toUpperCase())
                          }
                          placeholder="Opsional"
                          className="mt-0.5 w-full rounded-lg border border-zinc-300 px-2.5 py-2 text-sm outline-none focus:border-natalo-600"
                        />
                      </label>
                      <label className="block">
                        <span className="text-[10px] font-bold uppercase tracking-wide text-zinc-400">
                          Berat (gram)
                        </span>
                        <input
                          type="number"
                          value={row.weightGram}
                          onChange={(e) =>
                            updateRow(row.tempId, "weightGram", e.target.value)
                          }
                          min={1}
                          inputMode="numeric"
                          className="mt-0.5 w-full rounded-lg border border-zinc-300 px-2.5 py-2 text-sm outline-none focus:border-natalo-600"
                        />
                      </label>
                    </div>
                  </div>
                ))}
              </div>

              {/* Desktop table */}
              <div className="mt-3 hidden overflow-x-auto rounded-xl border border-zinc-200 md:block">
                <table className="w-full text-sm">
                  <thead className="bg-zinc-50 text-xs font-bold uppercase tracking-wide text-zinc-500">
                    <tr>
                      {/* Header per atribut — live, ikut nama yang admin ketik. */}
                      {nonEmptyAttrs.map((a, idx) => (
                        <th key={a.tempId} className="px-3 py-3 text-left">
                          <span className="mr-1 text-red-500">•</span>
                          {a.name || `Variasi ${idx + 1}`}
                        </th>
                      ))}
                      <th className="px-3 py-3 text-left">Foto Variasi</th>
                      <th className="px-3 py-3 text-left">
                        <span className="text-red-500">*</span> Harga
                      </th>
                      <th className="px-3 py-3 text-left">
                        <span className="text-red-500">*</span> Stok
                      </th>
                      <th className="px-3 py-3 text-left">Kode SKU</th>
                      <th className="px-3 py-3 text-left">Berat (gram)</th>
                      <th className="px-3 py-3 text-center">Aktif</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-100">
                    {rows.map((row) => {
                      const priceError =
                        showFieldErrors &&
                        row.isActive &&
                        (!row.price || Number(row.price) <= 0);
                      return (
                        <tr
                          key={row.tempId}
                          className={
                            row.isActive
                              ? "bg-white"
                              : "bg-zinc-50 opacity-60"
                          }
                        >
                          {/* Option value cells */}
                          {row.optionValues.map((val, i) => (
                            <td key={i} className="px-3 py-3 align-top">
                              <span className="rounded-lg bg-natalo-50 px-2 py-1 text-xs font-semibold text-natalo-700">
                                {val}
                              </span>
                            </td>
                          ))}

                          {/* Foto Variasi */}
                          <td className="px-3 py-3 align-top">
                            <VariantImageCell
                              imageUrl={row.imageUrl}
                              onChange={(url) =>
                                updateRow(row.tempId, "imageUrl", url)
                              }
                            />
                          </td>

                          {/* Harga */}
                          <td className="px-3 py-3 align-top">
                            <div className="relative">
                              <span className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
                                Rp
                              </span>
                              <input
                                type="number"
                                value={row.price}
                                onChange={(e) =>
                                  updateRow(row.tempId, "price", e.target.value)
                                }
                                placeholder="Input"
                                min={0}
                                className={`w-28 rounded-lg border bg-white pl-7 pr-2 py-1.5 text-sm outline-none focus:border-natalo-600 ${
                                  priceError ? "border-red-400" : "border-zinc-300"
                                }`}
                              />
                            </div>
                            {row.price && Number(row.price) > 0 && (
                              <p className="mt-0.5 text-[10px] text-zinc-400">
                                {formatRupiah(Number(row.price))}
                              </p>
                            )}
                            {priceError && (
                              <p className="mt-0.5 text-[10px] text-red-500">
                                Kolom wajib diisi
                              </p>
                            )}
                          </td>

                          {/* Stok */}
                          <td className="px-3 py-3 align-top">
                            <input
                              type="number"
                              value={row.stock}
                              onChange={(e) =>
                                updateRow(row.tempId, "stock", e.target.value)
                              }
                              min={0}
                              className="w-20 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-natalo-600"
                            />
                          </td>

                          {/* Kode SKU */}
                          <td className="px-3 py-3 align-top">
                            <input
                              type="text"
                              value={row.sku}
                              onChange={(e) =>
                                updateRow(row.tempId, "sku", e.target.value.toUpperCase())
                              }
                              placeholder="Opsional"
                              className="w-28 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-natalo-600"
                            />
                          </td>

                          {/* Berat (gram) */}
                          <td className="px-3 py-3 align-top">
                            <input
                              type="number"
                              value={row.weightGram}
                              onChange={(e) =>
                                updateRow(row.tempId, "weightGram", e.target.value)
                              }
                              min={1}
                              className="w-24 rounded-lg border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-natalo-600"
                            />
                          </td>

                          {/* Aktif toggle */}
                          <td className="px-3 py-3 text-center align-top">
                            <button
                              type="button"
                              onClick={() =>
                                updateRow(row.tempId, "isActive", !row.isActive)
                              }
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
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Banner kesalahan global — muncul setelah submit gagal */}
          {showFieldErrors && validationErrors.length > 0 && (
            <div className="flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4">
              <span className="text-red-500">⚠</span>
              <div className="flex-1 text-sm">
                <p className="font-semibold text-red-700">
                  Gagal menyimpan karena terdapat{" "}
                  {validationErrors.length} kesalahan, edit dahulu dan coba lagi.
                </p>
                <ul className="mt-2 space-y-1 text-red-600">
                  {validationErrors.map((e, i) => (
                    <li key={i}>• {e}</li>
                  ))}
                </ul>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Save button — hidden di draft mode (parent form punya save sendiri). */}
      {!isDraftMode && (
        <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
          <button
            type="button"
            onClick={handleSave}
            disabled={saving}
            className="w-full rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
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
      )}
    </div>
  );
}

// ── Sub-component: image upload cell per variant row ───────────
/**
 * Slot upload gambar prominent per variant. Click → file picker →
 * POST /api/admin/upload (UploadThing) → set imageUrl state.
 * Style: square placeholder 64×64 dengan dashed border kalau kosong,
 * preview gambar dengan tombol × hapus kalau sudah ada.
 */
function VariantImageCell({
  imageUrl,
  onChange,
}: {
  imageUrl: string;
  onChange: (url: string) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");

  async function handleFile(file: File) {
    if (file.size > 2 * 1024 * 1024) {
      setError("Maks 2 MB");
      return;
    }
    setError("");
    setUploading(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const res = await fetch("/api/admin/upload", { method: "POST", body: fd });
      if (!res.ok) throw new Error("Upload gagal");
      const data = await res.json();
      const url = String(data.url ?? "");
      if (!url) throw new Error("URL kosong dari server");
      onChange(url);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload gagal");
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  if (imageUrl) {
    return (
      <div className="relative inline-block">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={imageUrl}
          alt="Foto varian"
          className="h-16 w-16 rounded-lg border border-zinc-200 object-cover"
        />
        <button
          type="button"
          onClick={() => onChange("")}
          className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white hover:bg-red-600"
          title="Hapus foto"
        >
          ×
        </button>
      </div>
    );
  }

  return (
    <div>
      <button
        type="button"
        onClick={() => fileRef.current?.click()}
        disabled={uploading}
        className="flex h-16 w-16 items-center justify-center rounded-lg border-2 border-dashed border-zinc-300 bg-white text-zinc-400 transition hover:border-natalo-400 hover:text-natalo-600 disabled:cursor-wait disabled:opacity-50"
        title="Tambah foto varian"
      >
        {uploading ? (
          <span className="text-[10px] font-bold">...</span>
        ) : (
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
            <circle cx="8.5" cy="8.5" r="1.5" />
            <polyline points="21 15 16 10 5 21" />
          </svg>
        )}
      </button>
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) handleFile(f);
        }}
      />
      {error && <p className="mt-1 text-[10px] text-red-500">{error}</p>}
    </div>
  );
}
