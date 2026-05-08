"use client";

import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";

type PdpState = {
  hasVariants: boolean;
  canAdd: boolean; // varian sudah dipilih (atau produk tanpa varian) DAN tidak out-of-stock
  outOfStock: boolean;
  price: number;
};

type Props = {
  /** State awal — selalu dipakai untuk produk tanpa varian. Untuk varian akan di-override oleh event dari VariantSelector. */
  initialState: PdpState;
};

export function StickyAddToCartBar({ initialState }: Props) {
  const [state, setState] = useState<PdpState>(initialState);

  // Dengar update state dari VariantSelector / ProductActions
  useEffect(() => {
    function onState(e: Event) {
      const detail = (e as CustomEvent<PdpState>).detail;
      if (detail) setState(detail);
    }
    window.addEventListener("pdp-state", onState);
    return () => window.removeEventListener("pdp-state", onState);
  }, []);

  function handleClick(e: React.MouseEvent) {
    e.preventDefault();

    if (state.outOfStock) return;

    // Punya varian tapi belum dipilih → scroll ke selector
    if (state.hasVariants && !state.canAdd) {
      const target = document.getElementById("beli");
      target?.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }

    // Trigger add-to-cart di komponen yang punya logic-nya
    window.dispatchEvent(new CustomEvent("pdp-add-to-cart"));
  }

  const label = state.outOfStock
    ? "Stok Habis"
    : state.hasVariants && !state.canAdd
      ? "Pilih Varian"
      : "+ Keranjang";

  const disabled = state.outOfStock;

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={disabled}
      className="fixed inset-x-0 bottom-[70px] z-40 flex items-center gap-3 border-t border-gray-100 bg-white px-4 py-3 text-left shadow-[0_-4px_12px_rgba(0,0,0,0.06)] active:opacity-90 disabled:cursor-not-allowed md:hidden [padding-bottom:calc(12px+env(safe-area-inset-bottom))]"
    >
      <div className="min-w-0 flex-1">
        <p className="text-xs text-gray-500">
          {state.outOfStock
            ? "Status"
            : state.hasVariants && !state.canAdd
              ? "Mulai dari"
              : "Harga"}
        </p>
        <p className="truncate text-base font-black text-blue-600">
          {state.outOfStock ? "Stok habis" : formatRupiah(state.price)}
        </p>
      </div>
      <span
        className={`flex h-12 shrink-0 items-center justify-center rounded-full px-6 text-sm font-bold text-white ${
          disabled ? "bg-gray-300" : "bg-blue-500"
        }`}
      >
        {label}
      </span>
    </button>
  );
}
