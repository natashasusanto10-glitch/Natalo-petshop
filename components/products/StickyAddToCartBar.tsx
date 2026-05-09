"use client";

import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";

type PdpState = {
  hasVariants: boolean;
  canAdd: boolean;
  outOfStock: boolean;
  price: number;
};

type Props = {
  initialState: PdpState;
  waHref: string;
};

export function StickyAddToCartBar({ initialState, waHref }: Props) {
  const [state, setState] = useState<PdpState>(initialState);

  useEffect(() => {
    function onState(e: Event) {
      const detail = (e as CustomEvent<PdpState>).detail;
      if (detail) setState(detail);
    }
    window.addEventListener("pdp-state", onState);
    return () => window.removeEventListener("pdp-state", onState);
  }, []);

  function handleCommerceClick(e: React.MouseEvent, action: "cart" | "buy") {
    e.preventDefault();
    if (state.outOfStock) return;

    if (state.hasVariants && !state.canAdd) {
      document.getElementById("beli")?.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }

    window.dispatchEvent(new CustomEvent(action === "cart" ? "pdp-add-to-cart" : "pdp-buy-now"));
  }

  const buyLabel = state.outOfStock
    ? "Stok Habis"
    : state.hasVariants && !state.canAdd
      ? "Pilih Varian"
      : "Beli Sekarang";

  return (
    <div className="fixed inset-x-0 bottom-[70px] z-40 border-t border-gray-100 bg-white px-3 py-2 shadow-[0_-4px_16px_rgba(0,0,0,0.08)] md:hidden [padding-bottom:calc(8px+env(safe-area-inset-bottom))]">
      <div className="grid grid-cols-[0.9fr_1.15fr_1.35fr] gap-2">
        <a
          href={waHref}
          target="_blank"
          rel="noreferrer"
          className="flex h-11 items-center justify-center rounded-xl border border-green-200 bg-green-50 px-2 text-xs font-extrabold text-green-700 active:bg-green-100"
        >
          Chat WA
        </a>
        <button
          type="button"
          onClick={(event) => handleCommerceClick(event, "cart")}
          disabled={state.outOfStock}
          className="flex h-11 items-center justify-center rounded-xl border border-natalo-500 bg-white px-2 text-xs font-extrabold text-natalo-600 active:bg-natalo-50 disabled:cursor-not-allowed disabled:border-gray-200 disabled:text-gray-300"
        >
          + Keranjang
        </button>
        <button
          type="button"
          onClick={(event) => handleCommerceClick(event, "buy")}
          disabled={state.outOfStock}
          className={`flex h-11 items-center justify-center rounded-xl px-2 text-xs font-extrabold text-white active:opacity-90 ${
            state.outOfStock ? "cursor-not-allowed bg-gray-300" : "bg-natalo-600"
          }`}
        >
          {buyLabel}
        </button>
      </div>
      <p className="mt-1 text-center text-[11px] font-bold text-gray-400">
        {state.outOfStock ? "Stok habis" : formatRupiah(state.price)}
      </p>
    </div>
  );
}
