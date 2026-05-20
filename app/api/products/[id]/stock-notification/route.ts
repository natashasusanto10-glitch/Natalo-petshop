/**
 * Stock notification subscription API — pre-order out-of-stock.
 *
 * - GET    /api/products/[id]/stock-notification        → cek status subscribe
 * - POST   /api/products/[id]/stock-notification        → subscribe (upsert)
 * - DELETE /api/products/[id]/stock-notification        → unsubscribe
 *
 * Body POST/DELETE (optional):
 *   { variantId?: string }
 *
 * Auth: customer session required.
 *
 * Pattern: tap "Beri tahu saat tersedia" di product detail (Flutter)
 * dengan stock=0 → POST → record StockNotification. Saat admin update
 * stock 0 → >0, trigger sendBackInStockPush() yang dispatch push ke
 * semua subscriber + clear notifiedAt (untuk audit, row tetap exist).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

type Params = { params: { id: string } };

/** GET — cek apakah user sudah subscribe untuk product/variant ini. */
export async function GET(request: NextRequest, { params }: Params) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "LOGIN_REQUIRED", subscribed: false },
      { status: 401 },
    );
  }
  const productId = params.id;
  const variantId = request.nextUrl.searchParams.get("variantId") || null;

  const sub = await prisma.stockNotification
    .findFirst({
      where: {
        userId: session.sub,
        productId,
        variantId,
      },
      select: { id: true, notifiedAt: true, createdAt: true },
    })
    .catch(() => null);

  return NextResponse.json({
    subscribed: !!sub && sub.notifiedAt === null,
    notifiedAt: sub?.notifiedAt ?? null,
  });
}

/** POST — subscribe. Idempotent via upsert (re-subscribe = reset notifiedAt). */
export async function POST(request: NextRequest, { params }: Params) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      { error: "LOGIN_REQUIRED" },
      { status: 401 },
    );
  }

  const productId = params.id;
  const body = (await request.json().catch(() => ({}))) as {
    variantId?: string | null;
  };
  const variantId = body.variantId ?? null;

  // Verify product exists + still has stock=0 (sanity check, supaya tidak
  // subscribe ke produk yang sudah ready stock).
  const product = await prisma.product
    .findUnique({
      where: { id: productId },
      select: {
        id: true,
        stock: true,
        isActive: true,
        variants: variantId
          ? {
              where: { id: variantId },
              select: { id: true, stock: true, isActive: true },
            }
          : false,
      },
    })
    .catch(() => null);

  if (!product || !product.isActive) {
    return NextResponse.json(
      { error: "PRODUCT_NOT_FOUND" },
      { status: 404 },
    );
  }

  // Cek stock — kalau sudah tersedia, tidak perlu subscribe.
  if (variantId) {
    const variant = product.variants?.[0];
    if (!variant || !variant.isActive) {
      return NextResponse.json(
        { error: "VARIANT_NOT_FOUND" },
        { status: 404 },
      );
    }
    if (variant.stock > 0) {
      return NextResponse.json(
        { error: "ALREADY_IN_STOCK", subscribed: false },
        { status: 400 },
      );
    }
  } else if (product.stock > 0) {
    return NextResponse.json(
      { error: "ALREADY_IN_STOCK", subscribed: false },
      { status: 400 },
    );
  }

  // Upsert — re-subscribe akan reset notifiedAt ke null.
  // Note: Postgres NULL in unique = distinct, jadi upsert pakai compound key
  // dengan variantId perlu treat null sebagai literal. Workaround: query
  // dulu, lalu update/create.
  const existing = await prisma.stockNotification.findFirst({
    where: {
      userId: session.sub,
      productId,
      variantId,
    },
  });

  if (existing) {
    await prisma.stockNotification.update({
      where: { id: existing.id },
      data: { notifiedAt: null, createdAt: new Date() },
    });
  } else {
    await prisma.stockNotification.create({
      data: {
        userId: session.sub,
        productId,
        variantId,
      },
    });
  }

  return NextResponse.json({
    ok: true,
    subscribed: true,
    message: "Kamu akan dapat notifikasi saat produk tersedia.",
  });
}

/** DELETE — unsubscribe. */
export async function DELETE(request: NextRequest, { params }: Params) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "LOGIN_REQUIRED" }, { status: 401 });
  }

  const productId = params.id;
  const variantId = request.nextUrl.searchParams.get("variantId") || null;

  await prisma.stockNotification.deleteMany({
    where: {
      userId: session.sub,
      productId,
      variantId,
    },
  });

  return NextResponse.json({
    ok: true,
    subscribed: false,
    message: "Notifikasi restock dimatikan.",
  });
}
