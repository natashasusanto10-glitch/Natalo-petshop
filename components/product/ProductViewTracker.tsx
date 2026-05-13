"use client";

import { useEffect } from "react";

const STORAGE_KEY = "nat-recent-product-views";
const MAX_ITEMS = 30;

type Props = {
  productId: string;
  slug: string;
};

function readRecentIds() {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : [];
  } catch {
    return [];
  }
}

export function ProductViewTracker({ productId, slug }: Props) {
  useEffect(() => {
    const ids = readRecentIds();
    const next = [productId, ...ids.filter((id) => id !== productId)].slice(0, MAX_ITEMS);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));

    fetch(`/api/products/${encodeURIComponent(slug)}/view`, {
      method: "POST",
      cache: "no-store",
    }).catch(() => {});
  }, [productId, slug]);

  return null;
}
