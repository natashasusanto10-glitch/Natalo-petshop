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
          <h2 className="text-base font-black text-zinc-950">Logo Brand</h2>
          <p className="mt-0.5 text-xs font-semibold text-zinc-500">
            Atur maks. 12 brand utama. Drag kartu untuk mengubah urutan.
          </p>
        </div>
        <button
          type="submit"
          className="rounded-full bg-zinc-950 px-4 py-2 text-xs font-black text-white hover:bg-zinc-800"
        >
          Simpan Urutan
        </button>
      </div>

      <div className="mt-4 flex max-h-[132px] gap-2.5 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {items.map((brand, index) => (
          <div
            key={brand.id}
            draggable
            onDragStart={() => setDraggedId(brand.id)}
            onDragEnter={() => reorder(brand.id)}
            onDragOver={(event) => event.preventDefault()}
            onDragEnd={() => setDraggedId(null)}
            className={`relative flex h-[112px] w-[98px] shrink-0 cursor-grab flex-col items-center justify-center rounded-2xl border bg-zinc-50 px-2 py-2 text-center transition active:cursor-grabbing ${
              draggedId === brand.id
                ? "scale-[0.98] border-blue-300 bg-blue-50 opacity-80"
                : "border-zinc-200 hover:border-zinc-300"
            }`}
            title={`Urutan ${index + 1}: ${brand.name}`}
          >
            <span className="absolute left-2 top-2 grid h-5 min-w-5 place-items-center rounded-full bg-blue-600 px-1 text-[10px] font-black text-white shadow-sm">
              {index + 1}
            </span>
            <div className="flex h-12 w-16 items-center justify-center rounded-xl bg-white p-2 ring-1 ring-zinc-100">
              {brand.logoUrl ? (
                <img
                  src={brand.logoUrl}
                  alt=""
                  className="max-h-full max-w-full object-contain"
                  draggable={false}
                />
              ) : (
                <span className="text-[10px] font-black uppercase text-zinc-400">
                  {brand.name.slice(0, 2)}
                </span>
              )}
            </div>
            <p className="mt-2 line-clamp-2 text-[11px] font-bold leading-tight text-zinc-700">
              {brand.name}
            </p>
          </div>
        ))}
      </div>
    </form>
  );
}
