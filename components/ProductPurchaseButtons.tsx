"use client";

import { useEffect, useState } from "react";
import { ExternalLink } from "@/components/ExternalLink";

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

export function ProductPurchaseButtons({ initialState, waHref }: Props) {
  const [state, setState] = useState(initialState);

  useEffect(() => {
    function onState(e: Event) {
      const detail = (e as CustomEvent<PdpState>).detail;
      if (detail) setState(detail);
    }
    window.addEventListener("pdp-state", onState);
    return () => window.removeEventListener("pdp-state", onState);
  }, []);

  function handleCommerceClick(action: "cart" | "buy") {
    if (state.outOfStock) return;
    if (state.hasVariants && !state.canAdd) {
      document.getElementById("beli")?.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }
    window.dispatchEvent(new CustomEvent(action === "cart" ? "pdp-add-to-cart" : "pdp-buy-now"));
  }

  return (
    <div className="mt-4 hidden grid-cols-3 gap-2 md:grid">
      <ExternalLink
        href={waHref}
        className="flex h-12 items-center justify-center rounded-xl border border-green-200 bg-green-50 text-sm font-extrabold text-green-700"
      >
        Chat WA
      </ExternalLink>
      <button
        type="button"
        onClick={() => handleCommerceClick("cart")}
        disabled={state.outOfStock}
        className="h-12 rounded-xl border border-natalo-500 text-sm font-extrabold text-natalo-600 disabled:cursor-not-allowed disabled:border-gray-200 disabled:text-gray-300"
      >
        + Keranjang
      </button>
      <button
        type="button"
        onClick={() => handleCommerceClick("buy")}
        disabled={state.outOfStock}
        className="h-12 rounded-xl bg-natalo-600 text-sm font-extrabold text-white disabled:cursor-not-allowed disabled:bg-gray-300"
      >
        {state.outOfStock ? "Stok Habis" : "Beli Sekarang"}
      </button>
    </div>
  );
}
