/**
 * /api/admin/discounts/promo-toko
 *
 * GET  - List all ProductDiscount (admin can paginate later)
 * POST - Create new Promo Toko + assign produk
 *
 * Validasi:
 * - Periode: endsAt > startsAt + max 90 hari + tidak masa lalu (start)
 * - Tipe: PERCENTAGE 1-95, FIXED_AMOUNT > 0
 * - maxDiscountCap hanya untuk PERCENTAGE
 * - Multi-promo conflict (opsi 3c): produk yang sudah di promo aktif
 *   atau upcoming TIDAK BISA dipilih di promo baru
 */
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";

const createSchema = z
  .object({
    name: z.string().trim().min(1).max(200),
    discountType: z.enum(["PERCENTAGE", "FIXED_AMOUNT"]),
    discountValue: z.number().int().min(1).max(999_999_999),
    maxDiscountCap: z.number().int().min(0).max(999_999_999).optional().nullable(),
    startsAt: z.string().datetime().or(z.string()),
    endsAt: z.string().datetime().or(z.string()),
    productIds: z.array(z.string().trim().min(1)).min(1).max(500),
  })
  .superRefine((data, ctx) => {
    const start = new Date(data.startsAt);
    const end = new Date(data.endsAt);
    if (isNaN(start.getTime()) || isNaN(end.getTime())) {
      ctx.addIssue({
        code: "custom",
        message: "Format tanggal tidak valid",
        path: ["startsAt"],
      });
      return;
    }
    if (end <= start) {
      ctx.addIssue({
        code: "custom",
        message: "Waktu berakhir harus setelah waktu mulai",
        path: ["endsAt"],
      });
    }
    const ninetyDays = 90 * 24 * 60 * 60 * 1000;
    if (end.getTime() - start.getTime() > ninetyDays) {
      ctx.addIssue({
        code: "custom",
        message: "Periode promo maksimal 90 hari",
        path: ["endsAt"],
      });
    }
    if (data.discountType === "PERCENTAGE" && data.discountValue > 95) {
      ctx.addIssue({
        code: "custom",
        message: "Diskon persentase maksimal 95%",
        path: ["discountValue"],
      });
    }
    if (data.discountType === "FIXED_AMOUNT" && data.maxDiscountCap) {
      ctx.addIssue({
        code: "custom",
        message: "Max discount cap hanya berlaku untuk tipe persentase",
        path: ["maxDiscountCap"],
      });
    }
  });

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const discounts = await prisma.productDiscount.findMany({
    orderBy: [{ isActive: "desc" }, { createdAt: "desc" }],
    take: 100,
  });
  return NextResponse.json({ discounts });
}

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const parsed = createSchema.safeParse(await request.json().catch(() => null));
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

  // Cek konflik: produk yang sudah di promo aktif / upcoming TIDAK
  // BISA dipilih di promo baru. Pakai array overlap query (Postgres
  // && operator) — Prisma's `hasSome` di productIds.
  const now = new Date();
  const conflicting = await prisma.productDiscount.findMany({
    where: {
      isActive: true,
      endsAt: { gt: now }, // active atau upcoming (endsAt belum lewat)
      productIds: { hasSome: body.productIds },
    },
    select: { id: true, name: true, productIds: true },
  });
  if (conflicting.length > 0) {
    // Cari produk mana yang konflik
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

  // Validasi produk benar-benar ada
  const existingCount = await prisma.product.count({
    where: { id: { in: body.productIds } },
  });
  if (existingCount !== body.productIds.length) {
    return NextResponse.json(
      { error: "Sebagian produk tidak ditemukan" },
      { status: 400 },
    );
  }

  const discount = await prisma.productDiscount.create({
    data: {
      name: body.name.trim(),
      discountType: body.discountType,
      discountValue: body.discountValue,
      maxDiscountCap: body.maxDiscountCap ?? null,
      startsAt: new Date(body.startsAt),
      endsAt: new Date(body.endsAt),
      productIds: body.productIds,
      isActive: true,
    },
  });

  return NextResponse.json(discount, { status: 201 });
}
