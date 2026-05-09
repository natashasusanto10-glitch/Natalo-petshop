import { NextRequest, NextResponse } from "next/server";
import type { CartItem } from "@/lib/cart";
import { reconcileCartItemsWithStock } from "@/lib/cart-stock";
import { getCartStockSnapshots } from "@/lib/cart-stock-server";

function sanitizeItems(raw: unknown): CartItem[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Map<string, CartItem>();

  for (const value of raw) {
    if (!value || typeof value !== "object") continue;
    const item = value as Record<string, unknown>;
    const productId = typeof item.productId === "string" ? item.productId : "";
    const variantId =
      typeof item.variantId === "string" && item.variantId.length > 0 ? item.variantId : null;
    const quantity = Math.floor(Number(item.quantity));
    const price = Math.floor(Number(item.price));
    const weightGram = Math.floor(Number(item.weightGram));

    if (!productId || !Number.isFinite(quantity) || quantity < 1 || quantity > 9999) continue;
    if (!Number.isFinite(price) || price < 0) continue;

    const key = `${productId}:${variantId ?? ""}`;
    seen.set(key, {
      productId,
      variantId,
      variantLabel: typeof item.variantLabel === "string" ? item.variantLabel : null,
      name: typeof item.name === "string" ? item.name.slice(0, 200) : "",
      price,
      quantity,
      subtotal: price * quantity,
      weightGram: Number.isFinite(weightGram) && weightGram > 0 ? weightGram : 500,
      imageUrl: typeof item.imageUrl === "string" ? item.imageUrl.slice(0, 500) : null,
      stock: Number.isFinite(Number(item.stock)) ? Math.floor(Number(item.stock)) : null,
    });
  }

  return [...seen.values()];
}

export async function POST(request: NextRequest) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const items = sanitizeItems((body as { items?: unknown })?.items);
  const snapshots = await getCartStockSnapshots(items);
  const result = reconcileCartItemsWithStock(items, snapshots);

  return NextResponse.json(result);
}
