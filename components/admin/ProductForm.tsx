"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AdminPage,
  Button,
  FormField,
  SectionCard,
} from "@/components/admin/ui";
import { NumberInput } from "@/components/admin/ui/NumberInput";
import { AdminDisclosure } from "@/components/admin/ui/AdminDisclosure";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";
import { ProductCard } from "@/components/ProductCard";
import { mapCatalogProduct } from "@/lib/product/catalog-product";
import ProductMediaRail from "@/components/admin/ProductMediaRail";
import { BrandCombobox } from "@/components/admin/BrandCombobox";
import { CategoryCombobox } from "@/components/admin/CategoryCombobox";
import type { ProductVideoDraftHandle } from "@/components/admin/ProductVideoDraft";
import {
  VariantEditor,
  type VariantEditorDraftPayload,
} from "@/components/admin/VariantEditor";
import { AiDescriptionField } from "@/components/admin/AiDescriptionField";
import { productFormCopy } from "@/lib/product/product-form-copy";
import { parseDosageRules } from "@/lib/product-dosage";
export { productFormCopy } from "@/lib/product/product-form-copy";

export type ProductFormMode = "create" | "edit";

const PET_SPECIES = ["Kucing", "Anjing", "Ikan", "Burung", "Reptil", "Lainnya"];

type DosageRuleDraft = { minKg: string; maxKg: string; instruction: string };
function persistedVariantDraft(product?: ProductLike) {
  const attrs = (product?.variantAttrs ?? []).map((a, index) => ({
    name: a.name,
    position: index,
    options: a.options.map((o, optionIndex) => ({
      value: o.value,
      position: optionIndex,
    })),
  }));
  const optionRefs = new Map(
    (product?.variantAttrs ?? []).flatMap((a, index) =>
      a.options.map((o) => [o.id, `${index}:${o.value}`] as const)
    )
  );
  const variants = (product?.variants ?? []).map((v) => ({
    id: v.id,
    optionRefs: v.options
      .map((o) => optionRefs.get(o.optionId))
      .filter((x): x is `${number}:${string}` => Boolean(x)),
    price: v.price,
    stock: v.stock,
    weightGram: v.weightGram,
    sku: v.sku ?? undefined,
    imageUrl: v.imageUrl ?? undefined,
    isActive: v.isActive,
  }));
  return { attributes: attrs, variants };
}

const variantSignature = (draft: {
  attributes: VariantEditorDraftPayload["attributes"];
  variants: VariantEditorDraftPayload["variants"];
}) =>
  JSON.stringify({
    attributes: draft.attributes,
    variants: draft.variants
      .map(({ id: _id, ...row }) => ({
        ...row,
        optionRefs: [...row.optionRefs].sort(),
      }))
      .sort((a, b) =>
        a.optionRefs.join("|").localeCompare(b.optionRefs.join("|"))
      ),
  });

type ProductLike = {
  id?: string;
  slug?: string;
  isActive?: boolean;
  discountPrice?: number | null;
  memberPrice?: number | null;
  flashSaleEndsAt?: Date | null;
  avgRating?: number;
  reviewCount?: number;
  discountItems?: Array<{
    variantId: string | null;
    discountedPrice: number;
    discount: { endsAt: Date };
  }>;
  name?: string;
  description?: string;
  imageUrl?: string | null;
  gallery?: string[];
  categoryId?: string | null;
  brandId?: string | null;
  price?: number;
  stock?: number;
  weightGram?: number;
  sku?: string | null;
  hasVariants?: boolean;
  variantAttrs?: Array<{
    id: string;
    name: string;
    position: number;
    options: Array<{ id: string; value: string; position: number }>;
  }>;
  variants?: Array<{
    id: string;
    price: number;
    stock: number;
    weightGram: number;
    sku: string | null;
    imageUrl: string | null;
    isActive: boolean;
    options: Array<{ optionId: string }>;
  }>;
  videoUrl?: string | null;
  videoGuid?: string | null;
  videoStatus?: string | null;
  videoThumbnailUrl?: string | null;
  videoDurationSec?: number | null;
  careCategory?: string | null;
  targetSpecies?: string[];
  dosageRules?: unknown;
};

export function ProductForm({
  mode,
  categories,
  brands,
  initialProduct,
}: {
  mode: ProductFormMode;
  categories: Array<{ id: string; name: string }>;
  brands: Array<{ id: string; name: string }>;
  initialProduct?: ProductLike;
}) {
  const router = useRouter();
  const copy = productFormCopy(mode);
  const [name, setName] = useState(initialProduct?.name ?? "");
  const [description, setDescription] = useState(
    initialProduct?.description ?? ""
  );
  const [images, setImages] = useState<string[]>([
    ...(initialProduct?.imageUrl ? [initialProduct.imageUrl] : []),
    ...(initialProduct?.gallery ?? []),
  ]);
  const initialSnapshot = useRef({
    images: [...images],
    videoGuid: initialProduct?.videoGuid ?? null,
    videoStatus: initialProduct?.videoStatus ?? null,
    videoThumbnailUrl: initialProduct?.videoThumbnailUrl ?? null,
    videoDurationSec: initialProduct?.videoDurationSec ?? null,
  });
  const [categoryId, setCategoryId] = useState(
    initialProduct?.categoryId ?? ""
  );
  const [brandId, setBrandId] = useState(initialProduct?.brandId ?? "");
  const [brandsState, setBrandsState] = useState(brands);
  const [price, setPrice] = useState(String(initialProduct?.price ?? ""));
  const [stock, setStock] = useState(String(initialProduct?.stock ?? "0"));
  const [weightGram, setWeightGram] = useState(
    String(initialProduct?.weightGram ?? "500")
  );
  const [sku, setSku] = useState(initialProduct?.sku ?? "");
  const [variants, setVariants] = useState<VariantEditorDraftPayload>({
    hasVariants: initialProduct?.hasVariants ?? false,
    attributes: [],
    variants: [],
    validationErrors: [],
  });
  const [careCategory, setCareCategory] = useState(
    initialProduct?.careCategory ?? ""
  );
  const [targetSpecies, setTargetSpecies] = useState<string[]>(
    initialProduct?.targetSpecies ?? []
  );
  const [dosageRules, setDosageRules] = useState<DosageRuleDraft[]>(
    parseDosageRules(initialProduct?.dosageRules).map((r) => ({
      minKg: String(r.minKg),
      maxKg: r.maxKg === null ? "" : String(r.maxKg),
      instruction: r.instruction,
    }))
  );
  const [dosageExtractLoading, setDosageExtractLoading] = useState(false);
  const [dosageExtractError, setDosageExtractError] = useState<string | null>(
    null
  );
  const [error, setError] = useState<string | null>(null);
  const [variantErrors, setVariantErrors] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [variantBusy, setVariantBusy] = useState(false);
  const [videoIntent, setVideoIntent] = useState<"keep" | "remove" | "replace">(
    "keep"
  );
  const [draftVideo, setDraftVideo] = useState<{
    url: string;
    durationSec: number;
  } | null>(null);
  const [mediaBusy, setMediaBusy] = useState(false);
  const [isActive, setIsActive] = useState(initialProduct?.isActive ?? true);
  const [aiBusy, setAiBusy] = useState(false);
  const [dirty, setDirty] = useState(false);
  const dirtyRef = useRef(false);
  const [leaveOpen, setLeaveOpen] = useState(false);
  const pendingHref = useRef("/admin/products");
  const errorRef = useRef<HTMLParagraphElement>(null);
  useEffect(() => {
    dirtyRef.current = dirty;
  }, [dirty]);
  useEffect(() => {
    const warn = (event: BeforeUnloadEvent) => {
      if (dirtyRef.current) event.preventDefault();
    };
    const navigation = (event: MouseEvent) => {
      const anchor = (event.target as Element).closest<HTMLAnchorElement>(
        "a[href]"
      );
      if (
        !dirtyRef.current ||
        !anchor ||
        anchor.target === "_blank" ||
        event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey ||
        event.button !== 0
      )
        return;
      const url = new URL(anchor.href);
      if (
        url.pathname === location.pathname &&
        url.search === location.search &&
        url.hash
      )
        return;
      event.preventDefault();
      event.stopPropagation();
      pendingHref.current = anchor.href;
      setLeaveOpen(true);
    };
    window.addEventListener("beforeunload", warn);
    document.addEventListener("click", navigation, true);
    return () => {
      window.removeEventListener("beforeunload", warn);
      document.removeEventListener("click", navigation, true);
    };
  }, []);
  useEffect(() => {
    if (error) errorRef.current?.focus();
  }, [error]);
  const videoRef = useRef<ProductVideoDraftHandle>(null);
  const hasVariants = variants.hasVariants;

  const variantsChanged =
    mode === "create" ||
    hasVariants !== Boolean(initialProduct?.hasVariants) ||
    (hasVariants &&
      variantSignature({
        attributes: variants.attributes,
        variants: variants.variants.map(({ id: _id, ...row }) => row),
      }) !== variantSignature(persistedVariantDraft(initialProduct)));

  async function save() {
    if (saving || mediaBusy || variantBusy || aiBusy || dosageExtractLoading)
      return;
    setError(null);
    setVariantErrors([]);
    if (!name.trim() || !description.trim() || images.length < 1) {
      setError("Nama, deskripsi, dan minimal satu foto wajib diisi.");
      return;
    }
    if (
      !hasVariants &&
      ![
        [price, 1, 999999999],
        [weightGram, 1, 999999],
        [stock, 0, 999999],
      ].every(
        ([value, min, max]) =>
          /^\d+$/.test(String(value)) &&
          Number.isSafeInteger(Number(value)) &&
          Number(value) >= Number(min) &&
          Number(value) <= Number(max)
      )
    ) {
      setError("Harga, stok, dan berat produk harus valid.");
      return;
    }
    if (
      careCategory &&
      dosageRules.some((rule) => {
        if (
          ![rule.minKg, rule.maxKg, rule.instruction].some((value) =>
            value.trim()
          )
        )
          return false;
        const min = Number(rule.minKg.replace(",", ".")),
          max = Number(rule.maxKg.replace(",", "."));
        return (
          !rule.minKg.trim() ||
          !rule.instruction.trim() ||
          !Number.isFinite(min) ||
          min < 0 ||
          (rule.maxKg.trim() !== "" && (!Number.isFinite(max) || max <= min))
        );
      })
    ) {
      setError(
        "Lengkapi berat minimum dan instruksi dosis. Berat maksimum harus lebih besar daripada minimum, atau dikosongkan."
      );
      return;
    }
    setSaving(true);
    let createdId: string | undefined;
    let productUpdated = false;
    const rollbackDraft = persistedVariantDraft(initialProduct);
    const rollbackPayload =
      mode === "edit"
        ? {
            isActive: initialProduct?.isActive,
            careCategory: initialProduct?.careCategory,
            targetSpecies: initialProduct?.targetSpecies,
            dosageRules: initialProduct?.dosageRules,
            name: initialProduct?.name,
            description: initialProduct?.description,
            imageUrls: initialSnapshot.current.images,
            categoryId: initialProduct?.categoryId,
            brandId: initialProduct?.brandId,
            price: initialProduct?.price,
            stock: initialProduct?.stock,
            weightGram: initialProduct?.weightGram,
            sku: initialProduct?.sku,
            hasVariants: initialProduct?.hasVariants,
            ...rollbackDraft,
            video: {
              guid: initialSnapshot.current.videoGuid,
              status: initialSnapshot.current.videoStatus,
              thumbnailUrl: initialSnapshot.current.videoThumbnailUrl,
              durationSec: initialSnapshot.current.videoDurationSec,
            },
          }
        : null;
    if (
      hasVariants &&
      (variants.validationErrors?.length ||
        !variants.attributes.length ||
        !variants.variants.length ||
        !variants.variants.some((v) => v.isActive))
    ) {
      setError(
        variants.validationErrors?.[0] ??
          "Lengkapi atribut dan minimal satu varian aktif sebelum menyimpan."
      );
      setSaving(false);
      return;
    }
    const effective = hasVariants;
    const payload = {
      isActive,
      name: name.trim(),
      description: description.trim(),
      imageUrls: images,
      categoryId: categoryId || null,
      brandId: brandId || null,
      price: effective ? 0 : Math.round(Number(price)),
      stock: effective ? 0 : Math.round(Number(stock)),
      weightGram: effective ? 500 : Math.round(Number(weightGram)),
      sku: effective ? null : sku.trim() || null,
      hasVariants: effective,
      attributes: effective ? variants.attributes : [],
      variants: effective ? variants.variants : [],
      careCategory: careCategory || null,
      targetSpecies: careCategory ? targetSpecies : [],
      dosageRules: careCategory
        ? dosageRules
            .filter((r) => r.minKg.trim() !== "" && r.instruction.trim() !== "")
            .map((r) => ({
              minKg: Number(r.minKg.replace(",", ".")),
              maxKg:
                r.maxKg.trim() === ""
                  ? null
                  : Number(r.maxKg.replace(",", ".")),
              instruction: r.instruction.trim(),
            }))
        : null,
    };
    // Keep existing variant records untouched when only product information changes.
    if (rollbackPayload && !variantsChanged) {
      delete (rollbackPayload as Record<string, unknown>).hasVariants;
      delete (rollbackPayload as Record<string, unknown>).attributes;
      delete (rollbackPayload as Record<string, unknown>).variants;
    }
    const requestPayload: Record<string, unknown> = { ...payload };
    if (mode === "edit" && !variantsChanged) {
      delete requestPayload.hasVariants;
      delete requestPayload.attributes;
      delete requestPayload.variants;
      if (hasVariants) {
        delete requestPayload.price;
        delete requestPayload.stock;
        delete requestPayload.weightGram;
        delete requestPayload.sku;
      }
    }
    try {
      const video = await videoRef.current?.prepareForSave();
      const videoState = videoRef.current?.getDraftState();
      if (video)
        Object.assign(requestPayload, {
          video: { status: "uploading", durationSec: video.durationSec },
        });
      const url =
        mode === "create"
          ? "/api/admin/products"
          : `/api/admin/products/${initialProduct?.id}`;
      const res = await fetch(url, {
        method: mode === "create" ? "POST" : "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(requestPayload),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        const issues = Array.isArray(data?.issues) ? data.issues : [];
        if (issues.length > 0) {
          const details = issues.map(
            (issue: { path?: unknown[]; message?: string }) => {
              const path = Array.isArray(issue.path) ? issue.path : [];
              const index = typeof path[1] === "number" ? path[1] : null;
              const row = index === null ? null : variants.variants[index];
              const label =
                row?.optionRefs
                  ?.filter(Boolean)
                  .map((ref) => ref.replace(/^\d+:/, ""))
                  .join(" / ") ||
                (index === null ? "Varian" : `Varian #${index + 1}`);
              const field = typeof path[2] === "string" ? path[2] : "";
              const fieldLabel: Record<string, string> = {
                sku: "Kode SKU",
                price: "Harga",
                stock: "Stok",
                weightGram: "Berat",
                optionRefs: "Opsi/kombinasi",
              };
              const fieldText = fieldLabel[field] ?? (field || "Data varian");
              return `${label} — ${fieldText}: ${
                issue.message ?? "Nilai tidak valid"
              }`;
            }
          );
          setVariantErrors(details);
          throw new Error(
            `Gagal menyimpan: ${details.length} masalah pada varian. Periksa detail di editor varian.`
          );
        }
        // `fields` = detail per-field dari Zod (dikirim server sejak selalu).
        // JANGAN dibuang: kalau `error` masih generik (klien/route lama, atau
        // 500 non-JSON yang bikin `data` kosong), inilah satu-satunya petunjuk
        // field mana yang salah.
        const fieldDetail =
          data?.fields && typeof data.fields === "object"
            ? Object.entries(
                data.fields as Record<string, string[] | undefined>
              )
                .filter(
                  ([, messages]) =>
                    Array.isArray(messages) && messages.length > 0
                )
                .map(([field, messages]) => `${field}: ${messages![0]}`)
                .join(". ")
            : "";
        if (data?.error && fieldDetail && !String(data.error).includes(":"))
          throw new Error(`${data.error} (${fieldDetail})`);
        if (data?.error) throw new Error(String(data.error));
        if (fieldDetail) throw new Error(fieldDetail);
        throw new Error(
          `Gagal menyimpan produk (HTTP ${res.status}). Cek log server untuk detail.`
        );
      }
      createdId = data.id;
      productUpdated = true;
      if (video && data.id) {
        await videoRef.current?.commitAfterProductSave(data.id);
        if (mode === "create") {
          const finalized = await fetch(
            `/api/admin/products/${data.id}/finalize`,
            { method: "POST" }
          );
          if (!finalized.ok)
            throw new Error("Produk belum dapat difinalisasi.");
        }
      }
      if (
        mode === "edit" &&
        videoState?.removeRequested &&
        initialProduct?.id
      ) {
        const removed = await fetch(
          `/api/admin/products/${initialProduct.id}/video`,
          { method: "DELETE" }
        );
        if (!removed.ok) throw new Error("Video lama gagal dihapus.");
      }
      if (mode === "create" && video && data.id && !isActive) {
        const archived = await fetch(`/api/admin/products/${data.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ isActive: false }),
        });
        if (!archived.ok) throw new Error("Status arsip belum tersimpan.");
      }
      dirtyRef.current = false;
      setDirty(false);
      router.push("/admin/products");
      router.refresh();
    } catch (e) {
      let message = e instanceof Error ? e.message : "Gagal menyimpan produk.";
      const restore =
        mode === "create" && createdId
          ? {
              url: `/api/admin/products/${createdId}/compensate`,
              options: { method: "POST" },
            }
          : mode === "edit" &&
            productUpdated &&
            initialProduct?.id &&
            rollbackPayload
          ? {
              url: `/api/admin/products/${initialProduct.id}`,
              options: {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(rollbackPayload),
              },
            }
          : null;
      if (restore) {
        try {
          const response = await fetch(restore.url, restore.options);
          if (!response.ok) throw new Error("Pemulihan gagal.");
        } catch {
          message +=
            " Sebagian perubahan mungkin sudah tersimpan. Buka produk di tab baru untuk memeriksa kondisi terakhir sebelum mencoba lagi.";
        }
      }
      setError(message);
      setSaving(false);
    }
  }

  async function extractDosage() {
    if (!initialProduct?.id) return;
    setDosageExtractLoading(true);
    setDosageExtractError(null);
    try {
      const res = await fetch(
        `/api/admin/products/${initialProduct.id}/extract-dosage`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name, description }),
        }
      );
      const data = await res.json().catch(() => null);
      if (!res.ok) throw new Error(data?.error ?? "Gagal ekstrak dosis.");
      const rules = Array.isArray(data?.dosageRules) ? data.dosageRules : [];
      setDosageRules(
        rules.map(
          (r: {
            minKg: number;
            maxKg: number | null;
            instruction: string;
          }) => ({
            minKg: String(r.minKg),
            maxKg: r.maxKg === null ? "" : String(r.maxKg),
            instruction: r.instruction,
          })
        )
      );
    } catch (e) {
      setDosageExtractError(
        e instanceof Error ? e.message : "Gagal ekstrak dosis."
      );
    } finally {
      setDosageExtractLoading(false);
    }
  }

  const initialAttrs = initialProduct?.variantAttrs ?? [];
  const initialVariants = initialProduct?.variants ?? [];
  const preview = mapCatalogProduct({
    id: initialProduct?.id ?? "admin-preview",
    name: name || "Nama produk",
    slug: initialProduct?.slug ?? "admin-preview",
    description,
    price: Number(price) || 0,
    stock: Number(stock) || 0,
    weightGram: Number(weightGram) || 500,
    imageUrl: images[0] ?? null,
    gallery: images.slice(1),
    hasVariants,
    discountPrice:
      hasVariants && variantsChanged
        ? null
        : initialProduct?.discountPrice ?? null,
    memberPrice: initialProduct?.memberPrice ?? null,
    flashSaleEndsAt: initialProduct?.flashSaleEndsAt
      ? new Date(initialProduct.flashSaleEndsAt)
      : null,
    avgRating: initialProduct?.avgRating ?? 0,
    reviewCount: initialProduct?.reviewCount ?? 0,
    category: categoryId ? { id: categoryId, slug: "" } : null,
    brandId: brandId || null,
    brand: brandsState.find((b) => b.id === brandId) ?? null,
    videoStatus: draftVideo
      ? "ready"
      : videoIntent === "remove"
      ? null
      : initialProduct?.videoStatus ?? null,
    videoUrl:
      draftVideo?.url ??
      (videoIntent === "remove" ? null : initialProduct?.videoUrl ?? null),
    videoThumbnailUrl: initialProduct?.videoThumbnailUrl ?? null,
    videoDurationSec:
      draftVideo?.durationSec ?? initialProduct?.videoDurationSec ?? null,
    variants: variants.variants
      .filter((v) => v.isActive)
      .map((v, i) => ({
        id: v.id ?? `preview-${i}`,
        price: v.price,
        stock: v.stock,
      })),
    discountItems: (initialProduct?.discountItems ?? []).map((item) => ({
      ...item,
      discount: { endsAt: new Date(item.discount.endsAt) },
    })),
  });
  return (
    <AdminPage maxWidth="xl" className="admin-product-form">
      <a
        href="/admin/products"
        className="text-sm font-semibold text-slate-500"
      >
        ← Kembali ke produk
      </a>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
        <h1 className="admin-heading text-2xl md:text-3xl">{copy.title}</h1>
        <span className="rounded-md bg-blue-50 px-3 py-2 text-xs font-semibold text-blue-700">
          {mode === "create" ? "Belum disimpan" : isActive ? "Aktif" : "Arsip"}
        </span>
      </div>
      <nav aria-label="Bagian form" className="admin-form-jumps">
        <a href="#dasar">Informasi produk</a>
        <a href="#deskripsi">Deskripsi</a>
        <a href="#penjualan">Informasi penjualan</a>
        <a href="#pengiriman">Pengiriman</a>
      </nav>
      <form
        onChange={() => setDirty(true)}
        onSubmit={(e) => {
          e.preventDefault();
          if (!saving) void save();
        }}
      >
        <div className="admin-form-grid">
          <fieldset disabled={saving} className="admin-form-stack min-w-0">
            <section id="dasar">
              <SectionCard title="Informasi produk">
                <div className="space-y-5">
                  <FormField label="Foto produk" required>
                    <ProductMediaRail
                      images={images}
                      onImagesChange={(value) => {
                        setImages(value);
                        setDirty(true);
                      }}
                      onDraftVideoPreview={setDraftVideo}
                      onBusyChange={setMediaBusy}
                      videoDraftRef={videoRef}
                      video={{
                        videoGuid: initialProduct?.videoGuid,
                        videoStatus: initialProduct?.videoStatus,
                        videoThumbnailUrl: initialProduct?.videoThumbnailUrl,
                        videoDurationSec: initialProduct?.videoDurationSec,
                      }}
                      onVideoIntentChange={(intent) => {
                        setVideoIntent(intent);
                        setDirty(true);
                      }}
                    />
                  </FormField>
                  <FormField label="Nama produk" required>
                    <input
                      aria-label="Nama produk"
                      maxLength={200}
                      required
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      name="name"
                      className="admin-field-control"
                    />
                  </FormField>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <FormField label="Kategori">
                      <CategoryCombobox
                        value={categoryId}
                        onChange={(value) => {
                          setCategoryId(value);
                          setDirty(true);
                        }}
                        categories={categories}
                      />
                    </FormField>
                    <FormField label="Brand">
                      <BrandCombobox
                        value={brandId}
                        onChange={(value) => {
                          setBrandId(value);
                          setDirty(true);
                        }}
                        brands={brandsState}
                        onBrandCreated={(b) =>
                          setBrandsState((prev) => [...prev, b])
                        }
                      />
                    </FormField>
                  </div>
                </div>
              </SectionCard>
            </section>
            <section id="deskripsi">
              <SectionCard title="Deskripsi">
                <AiDescriptionField
                  onBusyChange={setAiBusy}
                  value={description}
                  onChange={(value) => {
                    setDescription(value);
                    setDirty(true);
                  }}
                  existingProductId={
                    mode === "edit" ? initialProduct?.id : undefined
                  }
                  context={{
                    name,
                    categoryName:
                      categories.find((c) => c.id === categoryId)?.name ?? null,
                    brandName:
                      brandsState.find((b) => b.id === brandId)?.name ?? null,
                    variants: variants.variants.map((v) => ({
                      optionValues: v.optionRefs,
                    })),
                  }}
                />
              </SectionCard>
            </section>
            <section id="penjualan">
              <SectionCard title="Informasi penjualan">
                <VariantEditor
                  onDirty={() => setDirty(true)}
                  onBusyChange={setVariantBusy}
                  initialHasVariants={initialProduct?.hasVariants ?? false}
                  initialAttributes={initialAttrs}
                  initialVariants={initialVariants}
                  onChange={setVariants}
                  externalErrors={variantErrors}
                />
                {!hasVariants && (
                  <div className="mt-5 grid gap-4 sm:grid-cols-2">
                    <FormField label="Harga" required>
                      <NumberInput
                        aria-label="Harga produk"
                        value={price}
                        onValueChange={setPrice}
                        className="admin-field-control"
                      />
                    </FormField>
                    <FormField label="Stok" required>
                      <NumberInput
                        aria-label="Stok produk"
                        value={stock}
                        thousands={false}
                        onValueChange={setStock}
                        className="admin-field-control"
                      />
                    </FormField>
                    <FormField label="SKU">
                      <input
                        aria-label="SKU produk"
                        maxLength={80}
                        value={sku}
                        onChange={(e) => setSku(e.target.value.toUpperCase())}
                        className="admin-field-control"
                      />
                    </FormField>
                  </div>
                )}
              </SectionCard>
            </section>
            <section id="pengiriman">
              <SectionCard title="Pengiriman">
                {hasVariants ? (
                  <p className="text-sm text-slate-500">
                    Berat diatur pada masing-masing varian.
                  </p>
                ) : (
                  <FormField label="Berat (gram)" required>
                    <NumberInput
                      aria-label="Berat produk dalam gram"
                      value={weightGram}
                      thousands={false}
                      onValueChange={setWeightGram}
                      className="admin-field-control max-w-xs"
                    />
                  </FormField>
                )}
              </SectionCard>
            </section>
            <AdminDisclosure id="perawatan" title="Perawatan (opsional)">
              <FormField
                label="Kategori Obat"
                hint="Aktifkan bila produk ini obat cacing/kutu untuk rekomendasi dosis otomatis."
              >
                <select
                  aria-label="Kategori obat"
                  value={careCategory}
                  onChange={(e) => setCareCategory(e.target.value)}
                  className="admin-field-control max-w-xs"
                >
                  <option value="">Bukan obat cacing/kutu</option>
                  <option value="deworm">Obat Cacing</option>
                  <option value="flea">Obat Kutu</option>
                </select>
              </FormField>
              {careCategory && (
                <>
                  <FormField
                    label="Spesies Target"
                    hint="Kosongkan semua untuk cocok semua spesies."
                  >
                    <div className="flex flex-wrap gap-3">
                      {PET_SPECIES.map((species) => (
                        <label
                          key={species}
                          className="flex items-center gap-2 rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                        >
                          <input
                            type="checkbox"
                            checked={targetSpecies.includes(species)}
                            onChange={(e) =>
                              setTargetSpecies((prev) =>
                                e.target.checked
                                  ? [...prev, species]
                                  : prev.filter((s) => s !== species)
                              )
                            }
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
                            <span
                              className="h-3 w-3 animate-spin rounded-full border-2 border-purple-400 border-t-transparent"
                              aria-hidden
                            />
                            Mengekstrak…
                          </>
                        ) : (
                          <>
                            <span>✨</span>
                            Ekstrak dosis dari deskripsi
                          </>
                        )}
                      </button>
                      {!initialProduct?.id && (
                        <span className="text-[11px] text-zinc-500">
                          Simpan produk dulu sebelum bisa ekstrak dosis.
                        </span>
                      )}
                    </div>
                    {dosageExtractError && (
                      <p className="mt-1 text-xs text-red-500">
                        ⚠️ {dosageExtractError}
                      </p>
                    )}
                    <div className="space-y-2">
                      {dosageRules.map((rule, index) => (
                        <div
                          key={index}
                          className="grid grid-cols-2 items-center gap-2 sm:grid-cols-[1fr_1fr_2fr_auto]"
                        >
                          <input
                            type="text"
                            inputMode="decimal"
                            aria-label={`Berat minimum dosis ${index + 1}`}
                            placeholder="Min kg"
                            value={rule.minKg}
                            onChange={(e) =>
                              setDosageRules((prev) =>
                                prev.map((r, i) =>
                                  i === index
                                    ? { ...r, minKg: e.target.value }
                                    : r
                                )
                              )
                            }
                            className="admin-field-control"
                          />
                          <input
                            type="text"
                            inputMode="decimal"
                            aria-label={`Berat maksimum dosis ${index + 1}`}
                            placeholder="Max kg (kosong = tanpa batas)"
                            value={rule.maxKg}
                            onChange={(e) =>
                              setDosageRules((prev) =>
                                prev.map((r, i) =>
                                  i === index
                                    ? { ...r, maxKg: e.target.value }
                                    : r
                                )
                              )
                            }
                            className="admin-field-control"
                          />
                          <input
                            type="text"
                            aria-label={`Instruksi dosis ${index + 1}`}
                            placeholder="Instruksi dosis"
                            value={rule.instruction}
                            onChange={(e) =>
                              setDosageRules((prev) =>
                                prev.map((r, i) =>
                                  i === index
                                    ? { ...r, instruction: e.target.value }
                                    : r
                                )
                              )
                            }
                            className="admin-field-control"
                          />
                          <Button
                            type="button"
                            variant="secondary"
                            onClick={() =>
                              setDosageRules((prev) =>
                                prev.filter((_, i) => i !== index)
                              )
                            }
                          >
                            Hapus
                          </Button>
                        </div>
                      ))}
                    </div>
                    <Button
                      type="button"
                      variant="secondary"
                      onClick={() =>
                        setDosageRules((prev) => [
                          ...prev,
                          { minKg: "", maxKg: "", instruction: "" },
                        ])
                      }
                      className="mt-2"
                    >
                      + Tambah baris
                    </Button>
                  </FormField>
                </>
              )}
            </AdminDisclosure>

            <SectionCard title="Status produk">
              <label className="flex min-h-11 items-center gap-3 text-sm">
                <input
                  type="checkbox"
                  checked={isActive}
                  onChange={(e) => setIsActive(e.target.checked)}
                />{" "}
                Tampilkan produk di katalog
              </label>
              <p className="mt-2 text-xs text-slate-500">
                Produk yang diarsipkan tetap tersimpan dan dapat diaktifkan
                kembali.
              </p>
            </SectionCard>
            {error && (
              <p
                ref={errorRef}
                tabIndex={-1}
                role="alert"
                className="rounded-xl bg-red-50 p-4 text-sm font-semibold text-red-700"
              >
                {error}
              </p>
            )}
          </fieldset>
          <aside className="admin-preview-panel">
            <p className="admin-preview-label">PRATINJAU KATALOG</p>
            <div className="admin-storefront-preview">
              <ProductCard
                product={preview}
                preview
                showCta={false}
                showRating
              />
            </div>
          </aside>
        </div>
        <div className="admin-savebar">
          <div className="text-xs text-slate-500" role="status">
            {saving
              ? "Menyimpan produk…"
              : dirty
              ? "Ada perubahan yang belum disimpan"
              : mode === "create"
              ? "Produk belum disimpan"
              : "Semua perubahan tersimpan"}
          </div>
          <div className="admin-save-actions flex gap-3">
            <Button
              type="button"
              variant="secondary"
              disabled={saving}
              onClick={() => {
                if (dirty) {
                  pendingHref.current = "/admin/products";
                  setLeaveOpen(true);
                } else router.push("/admin/products");
              }}
            >
              Batal
            </Button>
            <Button
              type="submit"
              disabled={
                saving ||
                mediaBusy ||
                variantBusy ||
                aiBusy ||
                dosageExtractLoading
              }
            >
              {saving ? "Menyimpan…" : copy.submit}
            </Button>
          </div>
        </div>
      </form>
      <AdminDialog
        open={leaveOpen}
        title="Perubahan belum disimpan"
        onClose={() => setLeaveOpen(false)}
        footer={
          <>
            <Button
              type="button"
              variant="secondary"
              onClick={() => setLeaveOpen(false)}
            >
              Tetap mengedit
            </Button>
            <Button
              type="button"
              onClick={() => {
                dirtyRef.current = false;
                setDirty(false);
                setLeaveOpen(false);
                window.location.assign(pendingHref.current);
              }}
            >
              Tinggalkan halaman
            </Button>
          </>
        }
      >
        <p className="text-sm text-slate-600">
          Perubahan pada produk ini akan hilang jika Anda meninggalkan halaman.
        </p>
      </AdminDialog>
    </AdminPage>
  );
}
