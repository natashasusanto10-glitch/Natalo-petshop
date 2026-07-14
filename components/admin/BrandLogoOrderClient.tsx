"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useAdminToast } from "@/components/admin/ui";

export type BrandLogoOrderItem = {
  id: string;
  name: string;
  logoUrl: string | null;
  isActive?: boolean;
};

type BrandLogoOrderClientProps = {
  brands: BrandLogoOrderItem[];
  otherBrands: BrandLogoOrderItem[];
  allBrandsPanel: ReactNode;
  saveAction: (formData: FormData) => Promise<void>;
  promoteAction: (brandId: string) => Promise<void>;
};

function moveItem<T>(items: T[], fromIndex: number, toIndex: number) {
  const next = [...items];
  const [picked] = next.splice(fromIndex, 1);
  next.splice(toIndex, 0, picked);
  return next;
}

function ImageIcon({ className = "h-5 w-5" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="4" y="5" width="16" height="14" rx="3" stroke="currentColor" strokeWidth="1.8" />
      <path d="m7 16 3.2-3.2a1.2 1.2 0 0 1 1.7 0L14 15l1.1-1.1a1.2 1.2 0 0 1 1.7 0L19 16" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="15.5" cy="9.5" r="1.25" fill="currentColor" />
    </svg>
  );
}

function DragHandle() {
  return (
    <span className="grid grid-cols-2 gap-0.5 text-zinc-400" aria-hidden="true">
      {Array.from({ length: 6 }).map((_, index) => (
        <span key={index} className="h-1 w-1 rounded-full bg-current" />
      ))}
    </span>
  );
}

function Logo({ brand }: { brand: BrandLogoOrderItem }) {
  return (
    <div className="flex h-11 w-16 items-center justify-center rounded-xl bg-white p-1.5 text-zinc-400 ring-1 ring-zinc-100">
      {brand.logoUrl ? (
        <img src={brand.logoUrl} alt="" className="max-h-full max-w-full object-contain" draggable={false} />
      ) : (
        <ImageIcon className="h-4 w-4" />
      )}
    </div>
  );
}

export function BrandLogoOrderClient({
  brands,
  otherBrands,
  allBrandsPanel,
  saveAction,
  promoteAction,
}: BrandLogoOrderClientProps) {
  const { show } = useAdminToast();
  const [activeTab, setActiveTab] = useState<"order" | "all">("order");
  const [items, setItems] = useState(brands);
  const [savedIds, setSavedIds] = useState(() => brands.map((item) => item.id));
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [promotingId, setPromotingId] = useState<string | null>(null);

  useEffect(() => {
    setItems(brands);
    setSavedIds(brands.map((item) => item.id));
  }, [brands]);

  const currentIds = useMemo(() => items.map((item) => item.id), [items]);
  const isDirty = currentIds.join("|") !== savedIds.join("|");

  function reorder(targetId: string) {
    if (!draggedId || draggedId === targetId) return;
    setItems((current) => {
      const fromIndex = current.findIndex((item) => item.id === draggedId);
      const toIndex = current.findIndex((item) => item.id === targetId);
      if (fromIndex < 0 || toIndex < 0) return current;
      return moveItem(current, fromIndex, toIndex);
    });
  }

  async function submitOrder() {
    if (!isDirty || saving) return;
    setSaving(true);
    const formData = new FormData();
    formData.set("orderedIds", JSON.stringify(currentIds));
    try {
      await saveAction(formData);
      setSavedIds(currentIds);
      show("Urutan brand berhasil disimpan.");
    } catch {
      show("Gagal menyimpan urutan brand. Coba lagi.");
    } finally {
      setSaving(false);
    }
  }

  async function promoteBrand(brandId: string) {
    if (promotingId) return;
    setPromotingId(brandId);
    try {
      await promoteAction(brandId);
      show("Brand dipindahkan ke urutan utama.");
    } catch {
      show("Brand belum dapat dipindahkan. Pastikan brand aktif dan memiliki logo.");
    } finally {
      setPromotingId(null);
    }
  }

  function renderBrandCard(brand: BrandLogoOrderItem, index: number) {
    return (
      <div
        key={brand.id}
        draggable
        onDragStart={() => setDraggedId(brand.id)}
        onDragEnter={() => reorder(brand.id)}
        onDragOver={(event) => event.preventDefault()}
        onDragEnd={() => setDraggedId(null)}
        className={`relative flex min-h-32 w-full cursor-grab items-center rounded-2xl border bg-white px-2 py-3 text-center transition active:cursor-grabbing sm:flex-col sm:justify-center ${
          draggedId === brand.id
            ? "scale-[0.98] border-blue-300 bg-blue-50 opacity-80 ring-2 ring-blue-100"
            : "border-zinc-200 hover:border-blue-300 hover:shadow-sm"
        }`}
        title={`Urutan ${index + 1}: ${brand.name}`}
      >
        <span className="absolute left-2 top-2 grid h-6 min-w-6 place-items-center rounded-full bg-blue-600 px-1 text-[10px] font-black text-white shadow-sm">
          {index + 1}
        </span>
        <span className="absolute bottom-3 left-3 sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2">
          <DragHandle />
        </span>
        <Logo brand={brand} />
        <p className="ml-3 line-clamp-2 text-xs font-bold leading-tight text-zinc-700 sm:ml-0 sm:mt-2">
          {brand.name}
        </p>
      </div>
    );
  }

  return (
    <section className="overflow-hidden rounded-3xl border border-zinc-200 bg-white shadow-sm">
      <div className="flex flex-col gap-4 border-b border-zinc-100 px-4 pt-4 sm:px-6 sm:pt-5 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex gap-6" role="tablist" aria-label="Pengelolaan brand">
          <button
            type="button"
            role="tab"
            aria-selected={activeTab === "order"}
            onClick={() => setActiveTab("order")}
            className={`border-b-2 px-1 pb-3 text-sm font-black transition ${activeTab === "order" ? "border-blue-600 text-blue-700" : "border-transparent text-zinc-500 hover:text-zinc-900"}`}
          >
            Urutan di Aplikasi
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={activeTab === "all"}
            onClick={() => setActiveTab("all")}
            className={`border-b-2 px-1 pb-3 text-sm font-black transition ${activeTab === "all" ? "border-blue-600 text-blue-700" : "border-transparent text-zinc-500 hover:text-zinc-900"}`}
          >
            Semua Brand
          </button>
        </div>

        {activeTab === "order" && (
          <div className="flex flex-wrap items-center gap-2 pb-4 lg:pb-3">
            {isDirty && (
              <span className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-bold text-amber-700">
                ⚠ Ada perubahan belum disimpan
              </span>
            )}
            <button
              type="button"
              disabled={!isDirty || saving}
              onClick={() => setItems(brands)}
              className="rounded-xl border border-zinc-200 px-4 py-2 text-xs font-bold text-zinc-600 transition hover:bg-zinc-50 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Batalkan
            </button>
            <button
              type="button"
              disabled={!isDirty || saving}
              onClick={() => void submitOrder()}
              className="rounded-xl bg-zinc-950 px-4 py-2 text-xs font-black text-white transition hover:bg-zinc-800 disabled:cursor-not-allowed disabled:bg-zinc-300"
            >
              {saving ? "Menyimpan..." : "Simpan Perubahan"}
            </button>
          </div>
        )}
      </div>

      {activeTab === "order" ? (
        <div className="p-4 sm:p-6" role="tabpanel">
          <div>
            <h2 className="text-base font-black text-zinc-950">Brand Utama</h2>
            <p className="mt-1 text-xs font-semibold text-zinc-500">
              Geser brand untuk mengatur urutan yang tampil di aplikasi. Maksimal 18 brand.
            </p>
          </div>

          {items.length === 0 ? (
            <div className="mt-5 rounded-2xl border border-dashed border-zinc-200 bg-zinc-50 p-8 text-center text-sm font-semibold text-zinc-500">
              Belum ada brand aktif dengan logo untuk diurutkan.
            </div>
          ) : (
            <div className="mt-5 grid grid-cols-1 gap-2.5 sm:grid-cols-3 md:grid-cols-6 xl:grid-cols-9">
              {items.map((brand, index) => renderBrandCard(brand, index))}
            </div>
          )}

          <div className="mt-7 border-t border-zinc-200 pt-6">
            <h3 className="text-base font-black text-zinc-950">Brand Lainnya</h3>
            <p className="mt-1 text-xs font-semibold text-zinc-500">
              Brand berikut belum masuk urutan utama atau perlu melengkapi logo dan status aktif.
            </p>
            {otherBrands.length === 0 ? (
              <p className="mt-4 rounded-2xl bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-700">
                Semua brand aktif sudah masuk urutan utama.
              </p>
            ) : (
              <div className="mt-4 divide-y divide-zinc-100 overflow-hidden rounded-2xl border border-zinc-200">
                {otherBrands.slice(0, 6).map((brand) => (
                  <div key={brand.id} className="flex items-center gap-3 px-4 py-3">
                    <Logo brand={brand} />
                    <p className="min-w-0 flex-1 truncate text-sm font-bold text-zinc-800">{brand.name}</p>
                    <span className={`rounded-full px-2.5 py-1 text-[10px] font-black ${brand.isActive === false ? "bg-zinc-100 text-zinc-600" : brand.logoUrl ? "bg-blue-50 text-blue-700" : "bg-amber-50 text-amber-700"}`}>
                      {brand.isActive === false ? "Nonaktif" : brand.logoUrl ? "Di luar 18 utama" : "Tanpa logo"}
                    </span>
                    {brand.isActive !== false && brand.logoUrl && (
                      <button
                        type="button"
                        disabled={promotingId !== null}
                        onClick={() => void promoteBrand(brand.id)}
                        className="hidden rounded-xl border border-zinc-200 px-3 py-2 text-[11px] font-black text-zinc-700 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 disabled:opacity-50 sm:block"
                      >
                        {promotingId === brand.id ? "Memindahkan..." : "↑ Pindahkan ke Atas"}
                      </button>
                    )}
                  </div>
                ))}
                {otherBrands.length > 6 && (
                  <button type="button" onClick={() => setActiveTab("all")} className="w-full px-4 py-3 text-xs font-black text-blue-700 hover:bg-blue-50">
                    Lihat {otherBrands.length - 6} brand lainnya
                  </button>
                )}
              </div>
            )}
          </div>
        </div>
      ) : (
        <div role="tabpanel">{allBrandsPanel}</div>
      )}
    </section>
  );
}
