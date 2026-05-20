/**
 * /api/admin/discounts/promo-toko/[id]
 *
 * GET    - Load single ProductDiscount untuk edit form
 * PUT    - Update (full replace, sama spec dengan POST)
 * DELETE - Hard delete (admin yakin)
 *
 * Edit constraint: kalau promo sudah ONGOING (start ≤ now), startsAt
 * TIDAK BISA diubah lagi — hanya endsAt + nilai diskon + productIds.
 * Sesuai pattern Shopee Seller (active promo lock start time).
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";

const updateSchema = z.object({
  name: z.string().trim().min(1).max(200),
  discountType: z.enum(["PERCENTAGE", "FIXED_AMOUNT"]),
  discountValue: z.number().int().min(1).max(999_999_999),
  maxDiscountCap: z.number().int().min(0).max(999_999_999).optional().nullable(),
  startsAt: z.string(),
  endsAt: z.string(),
  productIds: z.array(z.string().trim().min(1)).min(1).max(500),
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
  });
  if (!discount) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  // Sekalian fetch produk yang ikut promo untuk pre-fill product picker
  // di form edit. Filter active products saja.
  const products = await prisma.product.findMany({
    where: { id: { in: discount.productIds } },
    select: { id: true, name: true, imageUrl: true, price: true },
  });

  return NextResponse.json({ discount, products });
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

  // Active promo lock — kalau sudah ONGOING, startsAt tidak boleh diubah.
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

  // Conflict check — exclude promo yang sedang di-edit ini.
  const conflicting = await prisma.productDiscount.findMany({
    where: {
      id: { not: id },
      isActive: true,
      endsAt: { gt: now },
      productIds: { hasSome: body.productIds },
    },
    select: { id: true, name: true, productIds: true },
  });
  if (conflicting.length > 0) {
    const conflictingProductIds = new Set<string>();
    for (const c of conflicting) {
      for (const pid of c.productIds) {
        if (body.productIds.includes(pid)) {
          conflictingProductIds.add(pid);
        }
      }
    }
    return NextResponse.json(
      {
        error: "Ada produk yang sudah masuk promo aktif lain",
        conflictingProductIds: Array.from(conflictingProductIds),
        conflictingPromoNames: conflicting.map((c) => c.name),
      },
      { status: 409 },
    );
  }

  const updated = await prisma.productDiscount.update({
    where: { id },
    data: {
      name: body.name.trim(),
      discountType: body.discountType,
      discountValue: body.discountValue,
      maxDiscountCap: body.maxDiscountCap ?? null,
      startsAt: newStart,
      endsAt: newEnd,
      productIds: body.productIds,
      isActive: body.isActive ?? existing.isActive,
    },
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
