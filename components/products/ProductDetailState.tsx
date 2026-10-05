"use client";

import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import type { StoreProductVariant } from "@/lib/products";

type DetailState = {
  variant: StoreProductVariant | null;
  setVariant: (variant: StoreProductVariant | null) => void;
};
const Context = createContext<DetailState | null>(null);

export function ProductDetailState({ children }: { children: ReactNode }) {
  const [variant, setVariant] = useState<StoreProductVariant | null>(null);
  const value = useMemo(() => ({ variant, setVariant }), [variant]);
  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useProductDetailState() {
  return useContext(Context);
}
