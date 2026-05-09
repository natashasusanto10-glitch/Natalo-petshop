/**
 * GET /api/cart  — fetch user's server-side cart
 * PUT /api/cart  — replace user's server-side cart with provided items
 *
 * Hanya untuk member (CUSTOMER session). Guest tetap pakai localStorage saja.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { reconcileCartItemsWithStock } from "@/lib/cart-stock";
import { getCartStockSnapshots } from "@/lib/cart-stock-server";

type ApiCartItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  name: string;
  price: number;
  quantity: number;
  subtotal?: number;
  weightGram: number;
  imageUrl?: string | null;
  stock?: number | null;
};

function sanitizeItems(raw: unknown): ApiCartItem[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Map<string, ApiCartItem>();
  for (const r of raw) {
    if (!r || typeof r !== "object") continue;
    const item = r as Record<string, unknown>;
    const productId = typeof item.productId === "string" ? item.productId : null;
    const quantity = Number(item.quantity);
    const price = Number(item.price);
    const weightGram = Number(item.weightGram);
    if (!productId || !Number.isFinite(quantity) || quantity < 1 || quantity > 9999) continue;
    if (!Number.isFinite(price) || price < 0) continue;

    const variantId =
      typeof item.variantId === "string" && item.variantId.length > 0 ? item.variantId : null;
    const key = `${productId}:${variantId ?? ""}`;
    seen.set(key, {
      productId,
      variantId,
      variantLabel: typeof item.variantLabel === "string" ? item.variantLabel : null,
      name: typeof item.name === "string" ? item.name.slice(0, 200) : "",
      price: Math.floor(price),
      quantity: Math.floor(quantity),
      subtotal: Math.floor(price) * Math.floor(quantity),
      weightGram: Number.isFinite(weightGram) ? Math.floor(weightGram) : 500,
      imageUrl: typeof item.imageUrl === "string" ? item.imageUrl.slice(0, 500) : null,
      stock: Number.isFinite(Number(item.stock)) ? Math.floor(Number(item.stock)) : null,
    });
  }
  return Array.from(seen.values());
}

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) return NextResponse.json({ items: [] }, { status: 200 });

  const items = await prisma.cartItem.findMany({
    where: { userId: session.sub },
    orderBy: { updatedAt: "desc" },
  });

  const cartItems = items.map((i) => ({
    productId: i.productId,
    variantId: i.variantId,
    variantLabel: i.variantLabel,
    name: i.name,
    price: i.price,
    quantity: i.quantity,
    subtotal: i.price * i.quantity,
    weightGram: i.weightGram,
    imageUrl: i.imageUrl,
    stock: i.stock,
  }));
  const snapshots = await getCartStockSnapshots(cartItems);
  const result = reconcileCartItemsWithStock(cartItems, snapshots);

  return NextResponse.json({ items: result.items, stockIssues: result.issues });
}

export async function PUT(req: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const items = sanitizeItems((body as { items?: unknown })?.items);

  // Replace strategy: hapus semua, lalu insert ulang. Atomic via transaction.
  await prisma.$transaction([
    prisma.cartItem.deleteMany({ where: { userId: session.sub } }),
    ...(items.length > 0
      ? [
          prisma.cartItem.createMany({
            data: items.map((i) => ({
              userId: session.sub,
              productId: i.productId,
              variantId: i.variantId,
              variantLabel: i.variantLabel,
              name: i.name,
              price: i.price,
              quantity: i.quantity,
              weightGram: i.weightGram,
              imageUrl: i.imageUrl,
              stock: i.stock,
            })),
          }),
        ]
      : []),
  ]);

  return NextResponse.json({ ok: true, count: items.length });
}
