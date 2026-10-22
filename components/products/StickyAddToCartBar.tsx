"use client";

import { useEffect, useState } from "react";
import { ExternalLink } from "@/components/ExternalLink";
import { hapticTap } from "@/lib/native/haptics";
import { ChatIcon } from "@/components/chat/ChatIcon";
import { openChat } from "@/components/chat/ChatLauncher";
import { useChatUnread } from "@/components/chat/useChatUnread";

type PdpState = {
  hasVariants: boolean;
  canAdd: boolean;
  outOfStock: boolean;
  price: number;
};

type Props = {
  initialState: PdpState;
  waHref: string;
  productId: string;
  productName: string;
};

export function StickyAddToCartBar({ initialState, waHref, productId, productName }: Props) {
  const { chatEnabled } = useChatUnread();
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

    hapticTap();

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
    <div className="md:hidden">
    <div className="product-bottom-cta">
      <div className="flex w-full gap-2">
        {chatEnabled ? (
          <button
            type="button"
            aria-label="Tanya produk ini"
            onClick={() => openChat({ productId, productName })}
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-natalo-200 bg-white text-natalo-600 transition-transform duration-100 active:scale-95 active:bg-natalo-50"
          >
            <ChatIcon className="h-5 w-5" />
          </button>
        ) : (
          <ExternalLink
            href={waHref}
            className="btn-chat-wa flex h-11 items-center justify-center rounded-xl border border-green-200 bg-green-50 px-2 text-xs font-extrabold text-green-700 transition-transform duration-100 active:scale-95 active:bg-green-100"
          >
            Chat WA
          </ExternalLink>
        )}
        <button
          type="button"
          onClick={(event) => handleCommerceClick(event, "cart")}
          disabled={state.outOfStock}
          className="btn-add-cart flex h-11 items-center justify-center rounded-xl border border-natalo-500 bg-white px-2 text-xs font-extrabold text-natalo-600 transition-transform duration-100 active:scale-95 active:bg-natalo-50 disabled:cursor-not-allowed disabled:border-gray-200 disabled:text-gray-300 disabled:active:scale-100"
        >
          + Keranjang
        </button>
        <button
          type="button"
          onClick={(event) => handleCommerceClick(event, "buy")}
          disabled={state.outOfStock}
          className={`btn-buy-now flex h-11 items-center justify-center rounded-xl px-2 text-xs font-extrabold text-white transition-transform duration-100 active:scale-95 active:opacity-90 ${
            state.outOfStock ? "cursor-not-allowed bg-gray-300 active:scale-100" : "bg-natalo-600"
          }`}
        >
          {buyLabel}
        </button>
      </div>
    </div>
    </div>
  );
}
