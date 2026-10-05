"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { VariantPhotoField } from "./VariantPhotoField";
import { Button } from "@/components/admin/ui";
import { NumberInput } from "@/components/admin/ui/NumberInput";
import { LayoutMotion } from "@/components/admin/ui/Motion";
import {
  variantPersistenceMode,
} from "@/lib/product/variant-editor";
export { variantPersistenceMode } from "@/lib/product/variant-editor";

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
  identity?: string;
  sourceId?: string;
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

// Label field varian untuk pesan error dari server (path Zod → nama manusiawi).
const VARIANT_FIELD_LABEL: Record<string, string> = {
  sku: "Kode SKU",
  price: "Harga",
  stock: "Stok",
  weightGram: "Berat",
  optionRefs: "Opsi/kombinasi",
  imageUrl: "Foto",
};

/**
 * Ubah satu issue Zod dari server ({path, message}) jadi kalimat yang
 * menunjuk baris varian / atribut mana yang salah, mis:
 *   `Varian "Hair & Skin" — Kode SKU: SKU hanya boleh huruf, angka, _ dan -`
 */
function describeVariantIssue(
  issue: { path: (string | number)[]; message: string },
  rows: VariantRow[],
  attrs: Array<{ name: string }>
): string {
  const [root, idx, field] = issue.path;
  if (root === "variants" && typeof idx === "number") {
    const row = rows[idx];
    const label =
      row?.optionValues.filter(Boolean).join(" / ") || `Varian #${idx + 1}`;
    const f =
      typeof field === "string" ? VARIANT_FIELD_LABEL[field] ?? field : "";
    return `Varian "${label}"${f ? ` — ${f}` : ""}: ${issue.message}`;
  }
  if (root === "attributes" && typeof idx === "number") {
    return `Variasi "${attrs[idx]?.name ?? `#${idx + 1}`}": ${issue.message}`;
  }
  return issue.message;
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
    id?: string;
    optionRefs: string[];
    price: number;
    stock: number;
    weightGram: number;
    sku?: string;
    imageUrl?: string;
    isActive: boolean;
  }>;
  validationErrors?: string[];
};

interface Props {
  mode?: "controlled" | "standalone";
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
  /** Error validasi dari submit parent ProductForm. */
  externalErrors?: string[];
  onDirty?(): void;
  onBusyChange?(busy: boolean): void;
}

export function VariantEditor({
  mode,
  productId,
  initialHasVariants,
  initialAttributes,
  initialVariants,
  onChange,
  externalErrors = [],
  onDirty,
  onBusyChange,
}: Props) {
  const isDraftMode = mode === "controlled" || typeof onChange === "function";
  const [uploads, setUploads] = useState<Set<string>>(new Set());
  useEffect(() => {
    onBusyChange?.(uploads.size > 0);
  }, [uploads, onBusyChange]);
  function uploadBusy(id: string, busy: boolean) {
    setUploads((current) => {
      const next = new Set(current);
      if (busy) next.add(id);
      else next.delete(id);
      return next;
    });
  }
  const [hasVariants, setHasVariants] = useState(initialHasVariants);
  const [attrs, setAttrs] = useState<AttrDraft[]>(() =>
    [...initialAttributes]
      .sort((a, b) => a.position - b.position)
      .map((a) => ({
        tempId: uid(),
        name: a.name,
        options: [...a.options]
          .sort((x, y) => x.position - y.position)
          .map((o) => ({ tempId: uid(), value: o.value })),
      }))
  );
  const rowCache = useRef(new Map<string, VariantRow>());
  const [rows, setRows] = useState<VariantRow[]>([]);
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState<{ ok: boolean; text: string } | null>(
    null
  );
  /** Daftar alasan spesifik dari server (422) — ditampilkan per baris. */
  const [serverErrors, setServerErrors] = useState<string[] | null>(null);
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
      preservedRows.forEach((row) => {
        if (row.identity) rowCache.current.set(row.identity, row);
      });
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
        const key = combo.map((o) => o.tempId).join("|");

        // Preserve existing row data
        const existing =
          rowCache.current.get(key) ??
          preservedRows.find((r) =>
            r.identity
              ? r.identity === key
              : r.optionRefs.join("|") === optionRefs.join("|")
          );

        return {
          tempId: existing?.tempId ?? uid(),
          identity: key,
          sourceId: existing?.sourceId,
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

  // Seed once; changing option labels must not reset the edited rows.
  const seeded = useRef(false);
  useEffect(() => {
    if (seeded.current) return;
    seeded.current = true;
    if (!initialHasVariants || initialAttributes.length === 0) return;

    const initRows: VariantRow[] = [];

    // Map optionId → {attrIdx, value}
    const optionMap = new Map<string, { attrIdx: number; value: string }>();
    [...initialAttributes]
      .sort((a, b) => a.position - b.position)
      .forEach((a, idx) => {
        a.options.forEach((o) =>
          optionMap.set(o.id, { attrIdx: idx, value: o.value })
        );
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
        sourceId: v.id,
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
  }, [
    buildRows,
    initialAttributes,
    initialHasVariants,
    initialVariants,
    nonEmptyAttrs,
  ]);

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

  // Auto-maintain trailing empty slot: setiap atribut harus selalu punya
  // 1 input kosong di akhir sebagai "add affordance". Begitu admin ketik
  // di slot kosong itu, append 1 slot kosong baru.
  useEffect(() => {
    setAttrs((prev) => {
      let changed = false;
      const next = prev.map((a) => {
        const last = a.options[a.options.length - 1];
        if (
          (!last || last.value.trim().length > 0) &&
          a.options.filter((o) => o.value.trim()).length < 20
        ) {
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
    if (attrs.length >= 2) return;
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
  function updateOptionValue(
    attrTempId: string,
    optTempId: string,
    value: string
  ) {
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

  // ── Row handlers ──────────────────────────────────────────────
  function updateRow(
    tempId: string,
    field: keyof VariantRow,
    value: string | boolean
  ) {
    setRows((prev) =>
      prev.map((r) => (r.tempId === tempId ? { ...r, [field]: value } : r))
    );
  }

  function applyBulk() {
    setRows((prev) =>
      prev.map((r, idx) => ({
        ...r,
        ...(bulkPrice ? { price: bulkPrice } : {}),
        ...(bulkStock ? { stock: bulkStock } : {}),
        // BUG FIX: SKU harus unik per varian. Sebelumnya copy paste
        // value yang sama ke semua row → "Payload varian tidak valid:
        // SKU tidak boleh duplikat" saat save. Sekarang auto-suffix
        // dengan index (1-based) supaya tiap row unik.
        // Contoh: bulk "PP7KG" → row 1 "PP7KG-1", row 2 "PP7KG-2".
        // Kalau cuma 1 row, tidak perlu suffix.
        ...(bulkSku
          ? {
              sku:
                prev.length > 1
                  ? `${bulkSku.trim()}-${idx + 1}`
                  : bulkSku.trim(),
            }
          : {}),
        ...(bulkWeight ? { weightGram: bulkWeight } : {}),
      }))
    );
    setBulkPrice("");
    setBulkStock("");
    setBulkSku("");
    setBulkWeight("");
  }

  // ── Validasi ──────────────────────────────────────────────────
  const duplicateSkuGroups = useMemo(() => {
    const groups = new Map<string, VariantRow[]>();
    for (const row of rows) {
      const sku = row.sku.trim().toLowerCase();
      if (!sku) continue;
      groups.set(sku, [...(groups.get(sku) ?? []), row]);
    }
    return new Map([...groups].filter(([, group]) => group.length > 1));
  }, [rows]);
  const isDuplicateSku = (row: VariantRow) =>
    duplicateSkuGroups.has(row.sku.trim().toLowerCase());
  const validationErrors = useMemo(() => {
    const errs: string[] = [];
    if (!hasVariants) return errs;
    if (attrs.some((a) => !a.name.trim()))
      errs.push("Semua atribut harus punya nama.");
    if (nonEmptyAttrs.length === 0)
      errs.push("Tambah minimal 1 atribut dengan opsi terisi.");
    if (rows.length === 0)
      errs.push("Tambah minimal 1 opsi ke setiap atribut.");
    if (rows.length > 200)
      errs.push(
        "Maksimal 200 varian. Kurangi pilihan variasi sebelum menyimpan."
      );
    const activeRows = rows.filter((r) => r.isActive);
    if (activeRows.length === 0) errs.push("Minimal 1 varian harus aktif.");
    if (rows.some((r) => r.isActive && (!r.price || Number(r.price) <= 0)))
      errs.push("Semua varian aktif harus punya harga > 0.");
    if (rows.some((r) => r.sku.trim().length > 80))
      errs.push("Kode SKU maksimal 80 karakter.");
    for (const group of duplicateSkuGroups.values()) {
      const names = group.map((row) => row.optionValues.join(" / ")).join(", ");
      errs.push(
        `SKU "${group[0].sku.trim()}" dipakai pada varian ${names}. Isi kode berbeda untuk setiap varian, atau kosongkan SKU jika belum tersedia.`
      );
    }
    if (
      rows.some((r) => r.sku.trim() && !/^[A-Za-z0-9_-]+$/.test(r.sku.trim()))
    ) {
      errs.push("Kode SKU hanya boleh mengandung huruf, angka, _ dan -.");
    }
    if (
      rows.some(
        (r) => r.isActive && (!r.weightGram || Number(r.weightGram) <= 0)
      )
    ) {
      errs.push("Semua varian aktif harus punya berat > 0 gram.");
    }
    const validInt = (raw: string, min: number, max: number) =>
      /^\d+$/.test(raw) &&
      Number.isSafeInteger(Number(raw)) &&
      Number(raw) >= min &&
      Number(raw) <= max;
    if (rows.some((r) => !validInt(r.stock, 0, 999999)))
      errs.push("Stok harus bilangan bulat antara 0 dan 999.999.");
    if (
      rows.some((r) => !validInt(r.price || "0", r.isActive ? 1 : 0, 999999999))
    )
      errs.push("Harga varian harus bilangan bulat yang valid.");
    if (rows.some((r) => !validInt(r.weightGram, r.isActive ? 1 : 0, 999999)))
      errs.push(
        "Berat varian aktif harus 1–999.999 gram; varian tidak aktif dapat bernilai 0."
      );
    for (const attr of attrs) {
      const values = attr.options
        .map((o) => o.value.trim().toLowerCase())
        .filter(Boolean);
      if (!values.length)
        errs.push(`Isi opsi untuk ${attr.name || "variasi"}.`);
      if (new Set(values).size !== values.length)
        errs.push(`Opsi ${attr.name || "variasi"} tidak boleh duplikat.`);
    }
    const names = attrs.map((a) => a.name.trim().toLowerCase());
    if (new Set(names).size !== names.length)
      errs.push("Nama variasi tidak boleh duplikat.");
    return [...new Set(errs)];
  }, [hasVariants, attrs, nonEmptyAttrs, rows, duplicateSkuGroups]);

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
        id: r.sourceId,
        optionRefs: r.optionRefs,
        price: Number(r.price) || 0,
        stock: Number(r.stock) || 0,
        weightGram: Number(r.weightGram) || 0,
        sku: r.sku || undefined,
        imageUrl: r.imageUrl || undefined,
        isActive: r.isActive,
      })),
      validationErrors,
    });
  }, [hasVariants, nonEmptyAttrs, rows, onChange, validationErrors]);

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
    setServerErrors(null);
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
          id: r.sourceId,
          optionRefs: r.optionRefs,
          price: Number(r.price) || 0,
          stock: Number(r.stock) || 0,
          weightGram: Number(r.weightGram) || 0,
          sku: r.sku || undefined,
          imageUrl: r.imageUrl || undefined,
          isActive: r.isActive,
        })),
      };

      if (
        variantPersistenceMode(
          mode ?? (isDraftMode ? "controlled" : "standalone")
        ) === "parent-save"
      )
        return;
      const res = await fetch(`/api/admin/products/${productId}/variants`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const data = await res.json().catch(() => null);

      if (!res.ok) {
        // Server (422) kirim `issues` detail per-field → tampilkan alasan
        // spesifik per baris varian, bukan cuma "Payload varian tidak valid".
        const issues: Array<{ path: (string | number)[]; message: string }> =
          Array.isArray(data?.issues) ? data.issues : [];
        if (issues.length > 0) {
          setServerErrors(
            issues.map((iss) => describeVariantIssue(iss, rows, nonEmptyAttrs))
          );
          setSaveMsg({
            ok: false,
            text: `Gagal menyimpan — ${issues.length} masalah, lihat detail di bawah.`,
          });
        } else {
          setSaveMsg({ ok: false, text: data?.error ?? "Gagal menyimpan" });
        }
        return;
      }

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

  // Stable row keys preserve edited values and focus when option names change.
  return (
    <div
      className="space-y-5"
      onClickCapture={(event) => {
        if ((event.target as Element).closest("button")) onDirty?.();
      }}
    >
      <label className="flex min-h-11 items-center gap-3 text-sm font-semibold">
        <input
          type="checkbox"
          checked={hasVariants}
          onChange={(e) => {
            setHasVariants(e.target.checked);
            setSaveMsg(null);
            setServerErrors(null);
          }}
        />{" "}
        Produk memiliki variasi
      </label>
      {hasVariants && (
        <>
          <LayoutMotion
            revision={attrs.map((a) => a.tempId).join("|")}
            className="space-y-4"
          >
            {attrs.map((attr, index) => (
              <div
                key={attr.tempId}
                data-motion-key={attr.tempId}
                className="admin-variation-group"
              >
                <div className="flex items-end gap-3">
                  <label className="min-w-0 flex-1">
                    <span className="admin-field-label">
                      Nama variasi {index + 1}
                    </span>
                    <input
                      aria-label={`Nama variasi ${index + 1}`}
                      maxLength={50}
                      value={attr.name}
                      placeholder="Contoh: Rasa, Ukuran"
                      onChange={(e) =>
                        updateAttrName(attr.tempId, e.target.value)
                      }
                      className="admin-field-control"
                    />
                  </label>
                  <button
                    type="button"
                    className="admin-icon-button"
                    aria-label={`Hapus variasi ${attr.name || index + 1}`}
                    onClick={() => removeAttr(attr.tempId)}
                  >
                    ×
                  </button>
                </div>
                <p className="admin-field-label mt-4">Pilihan variasi</p>
                <LayoutMotion
                  revision={attr.options.map((o) => o.tempId).join("|")}
                  className="admin-variation-options"
                >
                  {attr.options.map((option, optionIndex) => (
                    <div
                      key={option.tempId}
                      data-motion-key={option.tempId}
                      className="flex items-center gap-2"
                    >
                      <input
                        aria-label={`Pilihan ${optionIndex + 1} untuk ${
                          attr.name || `variasi ${index + 1}`
                        }`}
                        maxLength={60}
                        value={option.value}
                        placeholder="Tambah pilihan"
                        aria-invalid={
                          showFieldErrors && isOptionRequiredEmpty(attr, option)
                        }
                        onChange={(e) =>
                          updateOptionValue(
                            attr.tempId,
                            option.tempId,
                            e.target.value
                          )
                        }
                        className="admin-field-control"
                      />
                      <button
                        type="button"
                        className="admin-icon-button"
                        aria-label={`Hapus pilihan ${
                          option.value || optionIndex + 1
                        }`}
                        onClick={() => removeOption(attr.tempId, option.tempId)}
                      >
                        ×
                      </button>
                    </div>
                  ))}
                </LayoutMotion>
              </div>
            ))}
          </LayoutMotion>
          {attrs.length < 2 && (
            <Button type="button" variant="secondary" onClick={addAttr}>
              + Tambah variasi {attrs.length + 1}
            </Button>
          )}
          {rows.length > 0 && (
            <>
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold">Daftar variasi</h3>
                <span className="text-xs text-slate-500">
                  {rows.length} varian
                </span>
              </div>
              <div className="admin-variant-bulk">
                <label>
                  <span className="admin-field-label">Harga</span>
                  <NumberInput
                    value={bulkPrice}
                    onValueChange={setBulkPrice}
                    placeholder="Harga"
                    className="admin-field-control"
                  />
                </label>
                <label>
                  <span className="admin-field-label">Stok</span>
                  <NumberInput
                    value={bulkStock}
                    onValueChange={setBulkStock}
                    thousands={false}
                    placeholder="Stok"
                    className="admin-field-control"
                  />
                </label>
                <label>
                  <span className="admin-field-label">Berat (gram)</span>
                  <NumberInput
                    value={bulkWeight}
                    onValueChange={setBulkWeight}
                    thousands={false}
                    placeholder="Berat"
                    className="admin-field-control"
                  />
                </label>
                <label>
                  <span className="admin-field-label">SKU</span>
                  <input
                    value={bulkSku}
                    onChange={(e) => setBulkSku(e.target.value)}
                    placeholder="Awalan SKU"
                    className="admin-field-control"
                  />
                </label>
                <Button
                  type="button"
                  variant="secondary"
                  onClick={applyBulk}
                  disabled={
                    ![bulkPrice, bulkStock, bulkWeight, bulkSku].some(Boolean)
                  }
                >
                  Terapkan ke semua
                </Button>
              </div>
              <LayoutMotion
                revision={rows.map((r) => r.tempId).join("|")}
                className="space-y-3 md:hidden"
              >
                {rows.map((row) => (
                  <div
                    key={row.tempId}
                    data-motion-key={row.tempId}
                    className="admin-variant-card"
                  >
                    <div className="mb-4 flex items-center gap-3">
                      <VariantPhotoField
                        onBusyChange={(busy) => uploadBusy(row.tempId, busy)}
                        imageUrl={row.imageUrl}
                        label={row.optionValues.join(" / ")}
                        onChange={(url) =>
                          updateRow(row.tempId, "imageUrl", url)
                        }
                      />
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-semibold">
                          {row.optionValues.join(" / ")}
                        </p>
                        <label className="mt-2 flex min-h-11 items-center gap-2 text-xs">
                          <input
                            type="checkbox"
                            checked={row.isActive}
                            onChange={(e) =>
                              updateRow(
                                row.tempId,
                                "isActive",
                                e.target.checked
                              )
                            }
                          />{" "}
                          Aktif
                        </label>
                      </div>
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      {(["price", "stock", "weightGram", "sku"] as const).map(
                        (field) => (
                          <label key={field}>
                            <span className="admin-field-label">
                              {VARIANT_FIELD_LABEL[field]}
                            </span>
                            {field === "sku" ? (
                              <input
                                value={row.sku}
                                aria-invalid={isDuplicateSku(row)}
                                aria-describedby={
                                  isDuplicateSku(row)
                                    ? `sku-duplicate-mobile-${row.tempId}`
                                    : undefined
                                }
                                maxLength={80}
                                onChange={(e) =>
                                  updateRow(row.tempId, field, e.target.value)
                                }
                                className={`admin-field-control ${
                                  isDuplicateSku(row) ? "!border-red-400" : ""
                                }`}
                              />
                            ) : (
                              <NumberInput
                                value={row[field]}
                                thousands={field === "price"}
                                onValueChange={(value) =>
                                  updateRow(row.tempId, field, value)
                                }
                                className="admin-field-control"
                              />
                            )}
                            {field === "sku" && isDuplicateSku(row) && (
                              <span
                                id={`sku-duplicate-mobile-${row.tempId}`}
                                className="mt-1 block text-xs text-red-600"
                              >
                                SKU dipakai varian lain di form ini.
                              </span>
                            )}
                          </label>
                        )
                      )}
                    </div>
                  </div>
                ))}
              </LayoutMotion>
              <div className="admin-variant-table hidden md:block">
                <table>
                  <thead>
                    <tr>
                      {nonEmptyAttrs.map((attr) => (
                        <th key={attr.tempId}>{attr.name}</th>
                      ))}
                      <th>Harga</th>
                      <th>Stok</th>
                      <th>SKU</th>
                      <th>Berat (gram)</th>
                      <th>Aktif</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((row) => (
                      <tr key={row.tempId}>
                        {row.optionValues.map((value, i) => (
                          <td key={i}>
                            <div className="flex items-center gap-4">
                              {i === 0 && (
                                <VariantPhotoField
                                  onBusyChange={(busy) => uploadBusy(row.tempId, busy)}
                                  imageUrl={row.imageUrl}
                                  label={row.optionValues.join(" / ")}
                                  onChange={(url) => updateRow(row.tempId, "imageUrl", url)}
                                />
                              )}
                              <span>{value}</span>
                            </div>
                          </td>
                        ))}
                        {(["price", "stock", "sku", "weightGram"] as const).map(
                          (field) => (
                            <td key={field}>
                              {field === "sku" ? (
                                <input
                                  aria-label={`SKU ${row.optionValues.join(
                                    " / "
                                  )}`}
                                  value={row.sku}
                                  aria-invalid={isDuplicateSku(row)}
                                  aria-describedby={
                                    isDuplicateSku(row)
                                      ? `sku-duplicate-desktop-${row.tempId}`
                                      : undefined
                                  }
                                  maxLength={80}
                                  onChange={(e) =>
                                    updateRow(row.tempId, field, e.target.value)
                                  }
                                  className={`admin-field-control ${
                                    isDuplicateSku(row) ? "!border-red-400" : ""
                                  }`}
                                />
                              ) : (
                                <NumberInput
                                  aria-label={`${
                                    VARIANT_FIELD_LABEL[field]
                                  } ${row.optionValues.join(" / ")}`}
                                  value={row[field]}
                                  thousands={field === "price"}
                                  onValueChange={(value) =>
                                    updateRow(row.tempId, field, value)
                                  }
                                  className="admin-field-control"
                                />
                              )}
                              {field === "sku" && isDuplicateSku(row) && (
                                <span
                                  id={`sku-duplicate-desktop-${row.tempId}`}
                                  className="mt-1 block text-xs text-red-600"
                                >
                                  SKU dipakai varian lain di form ini.
                                </span>
                              )}
                            </td>
                          )
                        )}
                        <td>
                          <input
                            aria-label={`Aktifkan ${row.optionValues.join(
                              " / "
                            )}`}
                            type="checkbox"
                            checked={row.isActive}
                            onChange={(e) =>
                              updateRow(
                                row.tempId,
                                "isActive",
                                e.target.checked
                              )
                            }
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
          {(showFieldErrors || externalErrors.length > 0) &&
            validationErrors.length > 0 && (
              <ul
                role="alert"
                className="space-y-1 rounded-lg bg-red-50 p-4 text-sm text-red-700"
              >
                {validationErrors.map((error) => (
                  <li key={error}>{error}</li>
                ))}
              </ul>
            )}
          {[...externalErrors, ...(serverErrors ?? [])].length > 0 && (
            <ul
              role="alert"
              className="space-y-1 rounded-lg bg-red-50 p-4 text-sm text-red-700"
            >
              {[...externalErrors, ...(serverErrors ?? [])].map((error, i) => (
                <li key={i}>{error}</li>
              ))}
            </ul>
          )}
        </>
      )}
      {!isDraftMode && (
        <Button
          type="button"
          onClick={() => void handleSave()}
          disabled={saving}
        >
          {saving ? "Menyimpan…" : "Simpan variasi"}
        </Button>
      )}
      {saveMsg && (
        <p
          role={saveMsg.ok ? "status" : "alert"}
          className={`text-sm ${
            saveMsg.ok ? "text-emerald-700" : "text-red-700"
          }`}
        >
          {saveMsg.text}
        </p>
      )}
    </div>
  );
}
