/**
 * /api/admin/discounts/promo-toko/[id]
 *
 * GET    - Load discount + items + product/variant details
 * PUT    - Update full replace (rebuild items)
 * DELETE - Hard delete (cascade ke items)
 *
 * Pattern: untuk PUT, delete semua items lalu recreate (atomic
 * transaction). Lebih simple dari diff-based update.
 *
 * Active promo lock: kalau status ONGOING (start <= now < end),
 * startsAt TIDAK boleh diubah (sesuai Shopee Seller pattern).
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";

const itemSchema = z.object({
  productId: z.string().trim().min(1),
  variantId: z.string().trim().min(1).optional().nullable(),
  discountedPrice: z.number().int().min(0).max(999_999_999),
  isItemActive: z.boolean().default(true),
});

const updateSchema = z.object({
  name: z.string().trim().min(1).max(150),
  startsAt: z.string(),
  endsAt: z.string(),
  items: z.array(itemSchema).min(1).max(500),
  isActive: z.boolean().optional(),
});

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const discount = await prisma.productDiscount.findUnique({
    where: { id },
    include: {
      items: {
        include: {
          product: {
            select: { id: true, name: true, imageUrl: true, price: true },
          },
          variant: {
            select: {
              id: true,
              sku: true,
              price: true,
              options: { select: { optionId: true } },
            },
          },
        },
      },
    },
  });
  if (!discount) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(discount);
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await prisma.productDiscount.findUnique({ where: { id } });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const parsed = updateSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: "Payload tidak valid",
        fields: parsed.error.flatten().fieldErrors,
      },
      { status: 400 },
    );
  }
  const body = parsed.data;

  const now = new Date();
  const newStart = new Date(body.startsAt);
  const newEnd = new Date(body.endsAt);
  if (isNaN(newStart.getTime()) || isNaN(newEnd.getTime())) {
    return NextResponse.json(
      { error: "Format tanggal tidak valid" },
      { status: 400 },
    );
  }
  if (newEnd <= newStart) {
    return NextResponse.json(
      { error: "Waktu berakhir harus setelah waktu mulai" },
      { status: 400 },
    );
  }
  const ninetyDays = 90 * 24 * 60 * 60 * 1000;
  if (newEnd.getTime() - newStart.getTime() > ninetyDays) {
    return NextResponse.json(
      { error: "Periode promo maksimal 90 hari" },
      { status: 400 },
    );
  }

  // Active promo lock — startsAt tidak boleh diubah kalau ONGOING.
  const isOngoing = existing.startsAt <= now && existing.endsAt > now;
  if (
    isOngoing &&
    Math.abs(newStart.getTime() - existing.startsAt.getTime()) > 60_000
  ) {
    return NextResponse.json(
      {
        error:
          "Promo yang sedang berjalan tidak bisa ubah waktu mulai. Hanya bisa ubah waktu berakhir + akhiri lebih awal.",
      },
      { status: 400 },
    );
  }

  // Conflict check exclude promo yang sedang di-edit.
  const productIds = Array.from(new Set(body.items.map((i) => i.productId)));
  const variantIds = body.items
    .map((i) => i.variantId)
    .filter((v): v is string => !!v);

  const conflictingItems = await prisma.productDiscountItem.findMany({
    where: {
      discountId: { not: id },
      productId: { in: productIds },
      OR: variantIds.length > 0
        ? [{ variantId: null }, { variantId: { in: variantIds } }]
        : [{ variantId: null }],
      discount: { isActive: true, endsAt: { gt: now } },
    },
    include: { discount: { select: { name: true } } },
  });
  const conflictingKeys = new Set(
    conflictingItems.map((i) => `${i.productId}::${i.variantId ?? ""}`),
  );
  const conflicts = body.items.filter((i) => {
    const key = `${i.productId}::${i.variantId ?? ""}`;
    return conflictingKeys.has(key);
  });
  if (conflicts.length > 0) {
    return NextResponse.json(
      {
        error: "Ada produk yang sudah masuk Promo Toko aktif lain",
        conflictingProductIds: Array.from(
          new Set(conflicts.map((c) => c.productId)),
        ),
        conflictingPromoNames: Array.from(
          new Set(conflictingItems.map((i) => i.discount.name)),
        ),
      },
      { status: 409 },
    );
  }

  // Rebuild — delete all old items, create new (atomic).
  const updated = await prisma.$transaction(async (tx) => {
    await tx.productDiscountItem.deleteMany({ where: { discountId: id } });
    return tx.productDiscount.update({
      where: { id },
      data: {
        name: body.name.trim(),
        startsAt: newStart,
        endsAt: newEnd,
        isActive: body.isActive ?? existing.isActive,
        items: {
          create: body.items.map((item) => ({
            productId: item.productId,
            variantId: item.variantId || null,
            discountedPrice: item.discountedPrice,
            isItemActive: item.isItemActive,
          })),
        },
      },
      include: { items: true },
    });
  });

  return NextResponse.json(updated);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await prisma.productDiscount.findUnique({ where: { id } });
  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  await prisma.productDiscount.delete({ where: { id } });
  return NextResponse.json({ ok: true });
}
