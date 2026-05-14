"use client";

import { useMemo, useState } from "react";

export type BrandLogoOrderItem = {
  id: string;
  name: string;
  logoUrl: string | null;
};

type BrandLogoOrderClientProps = {
  brands: BrandLogoOrderItem[];
  saveAction: (formData: FormData) => Promise<void>;
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
      <path
        d="m7 16 3.2-3.2a1.2 1.2 0 0 1 1.7 0L14 15l1.1-1.1a1.2 1.2 0 0 1 1.7 0L19 16"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="15.5" cy="9.5" r="1.25" fill="currentColor" />
    </svg>
  );
}

export function BrandLogoOrderClient({
  brands,
  saveAction,
}: BrandLogoOrderClientProps) {
  const [items, setItems] = useState(brands);
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const orderedIds = useMemo(() => JSON.stringify(items.map((item) => item.id)), [items]);

  function reorder(targetId: string) {
    if (!draggedId || draggedId === targetId) return;
    const fromIndex = items.findIndex((item) => item.id === draggedId);
    const toIndex = items.findIndex((item) => item.id === targetId);
    if (fromIndex < 0 || toIndex < 0) return;
    setItems(moveItem(items, fromIndex, toIndex));
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
        className={`relative flex h-[96px] w-[88px] shrink-0 cursor-grab flex-col items-center justify-center rounded-2xl border bg-zinc-50 px-2 py-2 text-center transition active:cursor-grabbing ${
          draggedId === brand.id
            ? "scale-[0.98] border-blue-300 bg-blue-50 opacity-80"
            : "border-zinc-200 hover:border-zinc-300"
        }`}
        title={`Urutan ${index + 1}: ${brand.name}`}
      >
        <span className="absolute left-1.5 top-1.5 grid h-5 min-w-5 place-items-center rounded-full bg-blue-600 px-1 text-[10px] font-black text-white shadow-sm">
          {index + 1}
        </span>
        <div className="flex h-10 w-14 items-center justify-center rounded-xl bg-white p-1.5 text-zinc-400 ring-1 ring-zinc-100">
          {brand.logoUrl ? (
            <img
              src={brand.logoUrl}
              alt=""
              className="max-h-full max-w-full object-contain"
              draggable={false}
            />
          ) : (
            <ImageIcon className="h-4 w-4" />
          )}
        </div>
        <p className="mt-1.5 line-clamp-2 text-[10px] font-bold leading-tight text-zinc-700">
          {brand.name}
        </p>
      </div>
    );
  }

  const firstRow = items.slice(0, 8);
  const secondRow = items.slice(8, 18);

  if (brands.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-zinc-200 bg-white p-5 text-center text-sm font-semibold text-zinc-500">
        Belum ada brand aktif dengan logo untuk diurutkan.
      </div>
    );
  }

  return (
    <form action={saveAction} className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <input type="hidden" name="orderedIds" value={orderedIds} />
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-black text-zinc-950">Urutan Brand Utama</h2>
          <p className="mt-0.5 text-xs font-semibold text-zinc-500">
            Atur 18 brand utama. Di luar grid ini otomatis tampil setelah urutan manual.
          </p>
        </div>
        <button
          type="submit"
          className="rounded-full bg-zinc-950 px-4 py-2 text-xs font-black text-white hover:bg-zinc-800"
        >
          Simpan Urutan
        </button>
      </div>

      <div className="mt-4 space-y-2.5 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <div className="grid min-w-max grid-cols-8 gap-2.5">
          {firstRow.map((brand, index) => renderBrandCard(brand, index))}
        </div>
        {secondRow.length > 0 && (
          <div className="grid min-w-max grid-cols-10 gap-2.5">
            {secondRow.map((brand, index) => renderBrandCard(brand, index + 8))}
          </div>
        )}
      </div>
    </form>
  );
}
