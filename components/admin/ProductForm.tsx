"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { AdminPage, Button, FormField, SectionCard } from "@/components/admin/ui";
import ProductMediaRail from "@/components/admin/ProductMediaRail";
import { BrandCombobox } from "@/components/admin/BrandCombobox";
import { CategoryCombobox } from "@/components/admin/CategoryCombobox";
import type { ProductVideoDraftHandle } from "@/components/admin/ProductVideoDraft";
import { VariantEditor, type VariantEditorDraftPayload } from "@/components/admin/VariantEditor";
import { AiDescriptionField } from "@/components/admin/AiDescriptionField";
import { productFormCopy } from "@/lib/product/product-form-copy";
import { parseDosageRules } from "@/lib/product-dosage";
export { productFormCopy } from "@/lib/product/product-form-copy";

export type ProductFormMode = "create" | "edit";

const PET_SPECIES = ["Kucing", "Anjing", "Ikan", "Burung", "Reptil", "Lainnya"];

type DosageRuleDraft = { minKg: string; maxKg: string; instruction: string };
function persistedVariantDraft(product?: ProductLike) {
  const attrs = (product?.variantAttrs ?? []).map((a, index) => ({ name: a.name, position: index, options: a.options.map((o, optionIndex) => ({ value: o.value, position: optionIndex })) }));
  const optionRefs = new Map((product?.variantAttrs ?? []).flatMap((a, index) => a.options.map(o => [o.id, `${index}:${o.value}`] as const)));
  const variants = (product?.variants ?? []).map(v => ({ optionRefs: v.options.map(o => optionRefs.get(o.optionId)).filter((x): x is `${number}:${string}` => Boolean(x)), price: v.price, stock: v.stock, weightGram: v.weightGram, sku: v.sku ?? undefined, imageUrl: v.imageUrl ?? undefined, isActive: v.isActive }));
  return { attributes: attrs, variants };
}

type ProductLike = {
  id?: string; name?: string; description?: string; imageUrl?: string | null; gallery?: string[];
  categoryId?: string | null; brandId?: string | null; price?: number; stock?: number; weightGram?: number; sku?: string | null;
  hasVariants?: boolean; variantAttrs?: Array<{ id: string; name: string; position: number; options: Array<{ id: string; value: string; position: number }> }>;
  variants?: Array<{ id: string; price: number; stock: number; weightGram: number; sku: string | null; imageUrl: string | null; isActive: boolean; options: Array<{ optionId: string }> }>;
  videoGuid?: string | null; videoStatus?: string | null; videoThumbnailUrl?: string | null; videoDurationSec?: number | null;
  careCategory?: string | null; targetSpecies?: string[]; dosageRules?: unknown;
};

export function ProductForm({ mode, categories, brands, initialProduct }: {
  mode: ProductFormMode;
  categories: Array<{ id: string; name: string }>;
  brands: Array<{ id: string; name: string }>;
  initialProduct?: ProductLike;
}) {
  const router = useRouter();
  const copy = productFormCopy(mode);
  const [name, setName] = useState(initialProduct?.name ?? "");
  const [description, setDescription] = useState(initialProduct?.description ?? "");
  const [images, setImages] = useState<string[]>([...(initialProduct?.imageUrl ? [initialProduct.imageUrl] : []), ...(initialProduct?.gallery ?? [])]);
  const initialSnapshot = useRef({ images: [...images], videoGuid: initialProduct?.videoGuid ?? null, videoStatus: initialProduct?.videoStatus ?? null, videoThumbnailUrl: initialProduct?.videoThumbnailUrl ?? null, videoDurationSec: initialProduct?.videoDurationSec ?? null });
  const [categoryId, setCategoryId] = useState(initialProduct?.categoryId ?? "");
  const [brandId, setBrandId] = useState(initialProduct?.brandId ?? "");
  const [brandsState, setBrandsState] = useState(brands);
  const [price, setPrice] = useState(String(initialProduct?.price ?? ""));
  const [stock, setStock] = useState(String(initialProduct?.stock ?? "0"));
  const [weightGram, setWeightGram] = useState(String(initialProduct?.weightGram ?? "500"));
  const [sku, setSku] = useState(initialProduct?.sku ?? "");
  const [variants, setVariants] = useState<VariantEditorDraftPayload>({ hasVariants: initialProduct?.hasVariants ?? false, attributes: [], variants: [], validationErrors: [] });
  const [careCategory, setCareCategory] = useState(initialProduct?.careCategory ?? "");
  const [targetSpecies, setTargetSpecies] = useState<string[]>(initialProduct?.targetSpecies ?? []);
  const [dosageRules, setDosageRules] = useState<DosageRuleDraft[]>(
    parseDosageRules(initialProduct?.dosageRules).map(r => ({ minKg: String(r.minKg), maxKg: r.maxKg === null ? "" : String(r.maxKg), instruction: r.instruction })),
  );
  const [dosageExtractLoading, setDosageExtractLoading] = useState(false);
  const [dosageExtractError, setDosageExtractError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [variantErrors, setVariantErrors] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const videoRef = useRef<ProductVideoDraftHandle>(null);
  const hasVariants = variants.hasVariants;

  async function save() {
    setError(null);
    setVariantErrors([]);
    if (!name.trim() || !description.trim() || images.length < 1) { setError("Nama, deskripsi, dan minimal satu foto wajib diisi."); return; }
    if (!hasVariants && (Number(price) <= 0 || Number(weightGram) <= 0 || Number(stock) < 0)) { setError("Harga, stok, dan berat produk harus valid."); return; }
    setSaving(true);
    let createdId: string | undefined;
    const rollbackDraft = persistedVariantDraft(initialProduct);
    const rollbackPayload = mode === "edit" ? { name: initialProduct?.name, description: initialProduct?.description, imageUrls: initialSnapshot.current.images, categoryId: initialProduct?.categoryId, brandId: initialProduct?.brandId, price: initialProduct?.price, stock: initialProduct?.stock, weightGram: initialProduct?.weightGram, sku: initialProduct?.sku, hasVariants: initialProduct?.hasVariants, ...rollbackDraft, video: { guid: initialSnapshot.current.videoGuid, status: initialSnapshot.current.videoStatus, thumbnailUrl: initialSnapshot.current.videoThumbnailUrl, durationSec: initialSnapshot.current.videoDurationSec } } : null;
    if (hasVariants && (variants.validationErrors?.length || !variants.attributes.length || !variants.variants.length || !variants.variants.some(v => v.isActive))) { setError(variants.validationErrors?.[0] ?? "Lengkapi atribut dan minimal satu varian aktif sebelum menyimpan."); setSaving(false); return; }
    const effective = hasVariants;
    const payload = {
      name: name.trim(), description: description.trim(), imageUrls: images,
      categoryId: categoryId || null, brandId: brandId || null,
      price: effective ? 0 : Math.round(Number(price)), stock: effective ? 0 : Math.round(Number(stock)), weightGram: effective ? 500 : Math.round(Number(weightGram)),
      sku: effective ? null : sku.trim() || null, hasVariants: effective, attributes: effective ? variants.attributes : [], variants: effective ? variants.variants : [],
      careCategory: careCategory || null,
      targetSpecies: careCategory ? targetSpecies : [],
      dosageRules: careCategory
        ? dosageRules
            .filter(r => r.minKg.trim() !== "" && r.instruction.trim() !== "")
            .map(r => ({ minKg: Number(r.minKg), maxKg: r.maxKg.trim() === "" ? null : Number(r.maxKg), instruction: r.instruction.trim() }))
        : null,
    };
    try {
      const video = await videoRef.current?.prepareForSave();
      const videoState = videoRef.current?.getDraftState();
      if (video) Object.assign(payload, { video: { status: "uploading", durationSec: video.durationSec } });
      const url = mode === "create" ? "/api/admin/products" : `/api/admin/products/${initialProduct?.id}`;
      const res = await fetch(url, { method: mode === "create" ? "POST" : "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        const issues = Array.isArray(data?.issues) ? data.issues : [];
        if (issues.length > 0) {
          const details = issues.map((issue: { path?: unknown[]; message?: string }) => {
            const path = Array.isArray(issue.path) ? issue.path : [];
            const index = typeof path[1] === "number" ? path[1] : null;
            const row = index === null ? null : variants.variants[index];
            const label = row?.optionRefs?.filter(Boolean).map(ref => ref.replace(/^\d+:/, "")).join(" / ") || (index === null ? "Varian" : `Varian #${index + 1}`);
            const field = typeof path[2] === "string" ? path[2] : "";
            const fieldLabel: Record<string, string> = { sku: "Kode SKU", price: "Harga", stock: "Stok", weightGram: "Berat", optionRefs: "Opsi/kombinasi" };
            const fieldText = fieldLabel[field] ?? (field || "Data varian");
            return `${label} — ${fieldText}: ${issue.message ?? "Nilai tidak valid"}`;
          });
          setVariantErrors(details);
          throw new Error(`Gagal menyimpan: ${details.length} masalah pada varian. Periksa detail di editor varian.`);
        }
        throw new Error(data.error ?? "Gagal menyimpan produk.");
      }
      createdId = data.id;
      if (video && data.id) { await videoRef.current?.commitAfterProductSave(data.id); if (mode === "create") { const finalized = await fetch(`/api/admin/products/${data.id}/finalize`, { method: "POST" }); if (!finalized.ok) throw new Error("Produk belum dapat difinalisasi."); } }
      if (mode === "edit" && videoState?.removeRequested && initialProduct?.id) { const removed = await fetch(`/api/admin/products/${initialProduct.id}/video`, { method: "DELETE" }); if (!removed.ok) throw new Error("Video lama gagal dihapus."); }
      router.push("/admin/products"); router.refresh();
    } catch (e) { if (mode === "create" && createdId) await fetch(`/api/admin/products/${createdId}/compensate`, { method: "POST" }).catch(() => undefined); if (mode === "edit" && initialProduct?.id && rollbackPayload) await fetch(`/api/admin/products/${initialProduct.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(rollbackPayload) }).catch(() => undefined); setError(e instanceof Error ? e.message : "Gagal menyimpan produk."); setSaving(false); }
  }

  async function extractDosage() {
    if (!initialProduct?.id) return;
    setDosageExtractLoading(true);
    setDosageExtractError(null);
    try {
      const res = await fetch(`/api/admin/products/${initialProduct.id}/extract-dosage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, description }),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) throw new Error(data?.error ?? "Gagal ekstrak dosis.");
      const rules = Array.isArray(data?.dosageRules) ? data.dosageRules : [];
      setDosageRules(rules.map((r: { minKg: number; maxKg: number | null; instruction: string }) => ({ minKg: String(r.minKg), maxKg: r.maxKg === null ? "" : String(r.maxKg), instruction: r.instruction })));
    } catch (e) {
      setDosageExtractError(e instanceof Error ? e.message : "Gagal ekstrak dosis.");
    } finally {
      setDosageExtractLoading(false);
    }
  }

  const initialAttrs = initialProduct?.variantAttrs ?? [];
  const initialVariants = initialProduct?.variants ?? [];
  return <AdminPage maxWidth="xl">
    <a href="/admin/products" className="text-sm font-bold text-zinc-500">← Kembali ke produk</a>
    <h1 className="mt-2 text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">{copy.title}</h1>
    <form onSubmit={e => { e.preventDefault(); void save(); }} className="mt-5 grid gap-6 md:grid-cols-[180px_minmax(0,1fr)]">
      <nav aria-label="Bagian form" className="hidden md:block"><div className="sticky top-6 space-y-1 rounded-2xl border border-zinc-200 bg-white p-2"><a href="#dasar" className="block rounded-lg px-3 py-2 text-sm font-semibold text-zinc-600">Informasi Dasar</a><a href="#penjualan" className="block rounded-lg px-3 py-2 text-sm font-semibold text-zinc-600">Informasi Penjualan</a><a href="#pengiriman" className="block rounded-lg px-3 py-2 text-sm font-semibold text-zinc-600">Pengiriman</a></div></nav>
      <div className="min-w-0 space-y-6">
        <SectionCard title="Informasi Dasar"><div id="dasar" className="space-y-5"><FormField label="Foto & Video Produk" required hint="Foto pertama menjadi cover. Maksimal 9 foto."><ProductMediaRail images={images} onImagesChange={setImages} videoDraftRef={videoRef} video={{ videoGuid: initialProduct?.videoGuid, videoStatus: initialProduct?.videoStatus, videoThumbnailUrl: initialProduct?.videoThumbnailUrl, videoDurationSec: initialProduct?.videoDurationSec }} onVideoIntentChange={() => undefined} /></FormField><FormField label="Nama Produk" required><input value={name} onChange={e => setName(e.target.value)} name="name" className="block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm" /></FormField><div className="grid gap-4 sm:grid-cols-2"><FormField label="Kategori"><CategoryCombobox value={categoryId} onChange={setCategoryId} categories={categories} /></FormField><FormField label="Brand"><BrandCombobox value={brandId} onChange={setBrandId} brands={brandsState} onBrandCreated={b => setBrandsState(prev => [...prev, b])} /></FormField></div><AiDescriptionField value={description} onChange={setDescription} existingProductId={mode === "edit" ? initialProduct?.id : undefined} context={{ name, categoryName: categories.find(c => c.id === categoryId)?.name ?? null, brandName: brandsState.find(b => b.id === brandId)?.name ?? null, variants: variants.variants.map(v => ({ optionValues: v.optionRefs })) }} /></div></SectionCard>
        <div id="penjualan"><SectionCard title="Informasi Penjualan"><VariantEditor initialHasVariants={initialProduct?.hasVariants ?? false} initialAttributes={initialAttrs} initialVariants={initialVariants} onChange={setVariants} externalErrors={variantErrors} /><div className="mt-5 grid gap-4 sm:grid-cols-2"><FormField label="Harga Satuan (Rp)" required={!hasVariants}><input type="number" disabled={hasVariants} value={hasVariants ? "" : price} onChange={e => setPrice(e.target.value)} className="block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm" /></FormField><FormField label="Stok" required={!hasVariants}><input type="number" disabled={hasVariants} value={hasVariants ? "" : stock} onChange={e => setStock(e.target.value)} className="block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm" /></FormField></div><FormField label="SKU Induk"><input disabled={hasVariants} value={hasVariants ? "" : sku} onChange={e => setSku(e.target.value.toUpperCase())} className="block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm" /></FormField></SectionCard></div>
        <div id="pengiriman"><SectionCard title="Pengiriman"><FormField label="Berat (gram)" required={!hasVariants}><input type="number" disabled={hasVariants} value={hasVariants ? "" : weightGram} onChange={e => setWeightGram(e.target.value)} className="block w-full max-w-xs rounded-xl border border-zinc-300 px-4 py-3 text-sm" /></FormField></SectionCard></div>
        <div id="perawatan"><SectionCard title="Perawatan (obat)">
          <FormField label="Kategori Obat" hint="Aktifkan bila produk ini obat cacing/kutu untuk rekomendasi dosis otomatis.">
            <select value={careCategory} onChange={e => setCareCategory(e.target.value)} className="block w-full max-w-xs rounded-xl border border-zinc-300 px-4 py-3 text-sm">
              <option value="">Bukan obat cacing/kutu</option>
              <option value="deworm">Obat Cacing</option>
              <option value="flea">Obat Kutu</option>
            </select>
          </FormField>
          {careCategory && <>
            <FormField label="Spesies Target" hint="Kosongkan semua untuk cocok semua spesies.">
              <div className="flex flex-wrap gap-3">
                {PET_SPECIES.map(species => (
                  <label key={species} className="flex items-center gap-2 rounded-lg border border-zinc-300 px-3 py-2 text-sm">
                    <input
                      type="checkbox"
                      checked={targetSpecies.includes(species)}
                      onChange={e => setTargetSpecies(prev => e.target.checked ? [...prev, species] : prev.filter(s => s !== species))}
                    />
                    {species}
                  </label>
                ))}
              </div>
            </FormField>
            <FormField label="Aturan Dosis">
              <div className="mb-2 flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void extractDosage()}
                  disabled={dosageExtractLoading || !initialProduct?.id}
                  className="inline-flex items-center gap-1.5 rounded-lg border-2 border-purple-300 bg-purple-50 px-3 py-1.5 text-xs font-bold text-purple-800 hover:bg-purple-100 disabled:cursor-not-allowed disabled:border-zinc-200 disabled:bg-zinc-50 disabled:text-zinc-400"
                >
                  {dosageExtractLoading ? (
                    <>
                      <span className="h-3 w-3 animate-spin rounded-full border-2 border-purple-400 border-t-transparent" aria-hidden />
                      Mengekstrak…
                    </>
                  ) : (
                    <>
                      <span>✨</span>
                      Ekstrak dosis dari deskripsi
                    </>
                  )}
                </button>
                {!initialProduct?.id && <span className="text-[11px] text-zinc-500">Simpan produk dulu sebelum bisa ekstrak dosis.</span>}
              </div>
              {dosageExtractError && <p className="mt-1 text-xs text-red-500">⚠️ {dosageExtractError}</p>}
              <div className="space-y-2">
                {dosageRules.map((rule, index) => (
                  <div key={index} className="grid grid-cols-[1fr_1fr_2fr_auto] items-center gap-2">
                    <input type="number" placeholder="Min kg" value={rule.minKg} onChange={e => setDosageRules(prev => prev.map((r, i) => i === index ? { ...r, minKg: e.target.value } : r))} className="block w-full rounded-xl border border-zinc-300 px-3 py-2 text-sm" />
                    <input type="number" placeholder="Max kg (kosong = tanpa batas)" value={rule.maxKg} onChange={e => setDosageRules(prev => prev.map((r, i) => i === index ? { ...r, maxKg: e.target.value } : r))} className="block w-full rounded-xl border border-zinc-300 px-3 py-2 text-sm" />
                    <input type="text" placeholder="Instruksi dosis" value={rule.instruction} onChange={e => setDosageRules(prev => prev.map((r, i) => i === index ? { ...r, instruction: e.target.value } : r))} className="block w-full rounded-xl border border-zinc-300 px-3 py-2 text-sm" />
                    <Button type="button" variant="secondary" onClick={() => setDosageRules(prev => prev.filter((_, i) => i !== index))}>Hapus</Button>
                  </div>
                ))}
              </div>
              <Button type="button" variant="secondary" onClick={() => setDosageRules(prev => [...prev, { minKg: "", maxKg: "", instruction: "" }])} className="mt-2">+ Tambah baris</Button>
            </FormField>
          </>}
        </SectionCard></div>
      </div>
    {error && <p className="mt-4 rounded-xl bg-red-50 p-4 text-sm font-semibold text-red-700">{error}</p>}
    <div className="sticky bottom-4 z-20 mt-6 flex justify-end gap-3 rounded-2xl border border-zinc-200 bg-white/95 px-4 py-3 shadow-lg"><Button href="/admin/products" variant="secondary">Batal</Button><Button type="submit" disabled={saving}>{saving ? "Menyimpan..." : copy.submit}</Button></div>
    </form>
  </AdminPage>;
}
