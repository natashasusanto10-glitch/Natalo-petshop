import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { validateReorderByOrderId } from "@/lib/reorder";
import { prisma } from "@/lib/prisma";
import {
  buildBuyAgainResponse,
  candidateToUnavailable,
  getBuyAgainCandidates,
  skippedToUnavailable,
  toBuyAgainAddedItem,
  type BuyAgainAddedItem,
  type BuyAgainUnavailableItem,
} from "@/lib/buy-again";
import type { CartItem } from "@/lib/cart";

function cartKey(productId: string, variantId?: string | null) {
  return `${productId}:${variantId ?? ""}`;
}

function toCartItem(item: {
  productId: string;
  variantId: string | null;
  variantLabel: string | null;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
  imageUrl: string | null;
  stock: number | null;
}): CartItem {
  return {
    productId: item.productId,
    variantId: item.variantId,
    variantLabel: item.variantLabel,
    name: item.name,
    price: item.price,
    quantity: item.quantity,
    subtotal: item.price * item.quantity,
    weightGram: item.weightGram,
    imageUrl: item.imageUrl,
    stock: item.stock,
  };
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderId: string }> },
) {
  try {
    const session = await getSession("CUSTOMER");
    if (!session) {
      return NextResponse.json(
        { error: "Silakan login terlebih dahulu." },
        { status: 401 },
      );
    }

    const { orderId } = await params;
    const body = await request.json().catch(() => ({}));
    const onlyItemId =
      typeof body.itemId === "string" && body.itemId.length > 0
        ? body.itemId
        : undefined;

    const result = await validateReorderByOrderId(orderId, session.sub, {
      onlyItemId,
    });

    const candidates = getBuyAgainCandidates(result);
    const addedItems: BuyAgainAddedItem[] = [];
    const unavailableItems: BuyAgainUnavailableItem[] =
      result.skipped.map(skippedToUnavailable);
    let cartItems: CartItem[] = [];

    await prisma.$transaction(async (tx) => {
      const existingCart = await tx.cartItem.findMany({
        where: { userId: session.sub },
      });
      const existingByKey = new Map(
        existingCart.map((item) => [
          cartKey(item.productId, item.variantId),
          {
            id: item.id,
            quantity: item.quantity,
          },
        ]),
      );

      for (const candidate of candidates) {
        const key = cartKey(candidate.item.productId, candidate.item.variantId);
        const existing = existingByKey.get(key);
        const existingQty = existing?.quantity ?? 0;
        const remainingStock = Math.max(0, candidate.availableStock - existingQty);
        const addedQty = Math.min(candidate.item.quantity, remainingStock);

        if (addedQty <= 0) {
          unavailableItems.push(
            candidateToUnavailable(
              candidate,
              "Jumlah di keranjang sudah mencapai stok tersedia.",
            ),
          );
          continue;
        }

        const nextQuantity = existingQty + addedQty;
        if (existing) {
          await tx.cartItem.update({
            where: { id: existing.id },
            data: {
              variantLabel: candidate.item.variantLabel,
              name: candidate.item.name,
              price: candidate.item.price,
              quantity: nextQuantity,
              weightGram: candidate.item.weightGram,
              imageUrl: candidate.item.imageUrl,
              stock: candidate.availableStock,
            },
          });
          existingByKey.set(key, { id: existing.id, quantity: nextQuantity });
        } else {
          const created = await tx.cartItem.create({
            data: {
              userId: session.sub,
              productId: candidate.item.productId,
              variantId: candidate.item.variantId,
              variantLabel: candidate.item.variantLabel,
              name: candidate.item.name,
              price: candidate.item.price,
              quantity: addedQty,
              weightGram: candidate.item.weightGram,
              imageUrl: candidate.item.imageUrl,
              stock: candidate.availableStock,
            },
          });
          existingByKey.set(key, { id: created.id, quantity: addedQty });
        }

        addedItems.push(toBuyAgainAddedItem(candidate, addedQty));
      }

      const latestCart = await tx.cartItem.findMany({
        where: { userId: session.sub },
        orderBy: { updatedAt: "desc" },
      });
      cartItems = latestCart.map(toCartItem);
    });

    const totalItems = cartItems.reduce((sum, item) => sum + item.quantity, 0);
    return NextResponse.json(
      buildBuyAgainResponse(addedItems, unavailableItems, totalItems, cartItems),
    );
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Gagal memproses beli lagi.";
    const status = message.includes("tidak ditemukan") ? 404 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
