/**
 * /api/admin/discounts/promo-toko
 *
 * GET  - List all ProductDiscount campaigns
 * POST - Create new Promo Toko + assign produk/varian dengan
 *        harga diskon per-item.
 *
 * Schema baru (refactor dari Phase 1B v1):
 *   ProductDiscount { id, name, startsAt, endsAt, isActive }
 *   ProductDiscountItem { discountId, productId, variantId?,
 *                         discountedPrice, isItemActive }
 *
 * Payload POST:
 *   { name, startsAt, endsAt, items: [
 *       { productId, variantId?, discountedPrice, isItemActive }
 *   ] }
 */
import { NextRequest, NextResponse, after } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { sendProductDiscountPromoPush } from "@/lib/push-promo";

const itemSchema = z.object({
  productId: z.string().trim().min(1),
  variantId: z.string().trim().min(1).optional().nullable(),
  discountedPrice: z.number().int().min(0).max(999_999_999),
  isItemActive: z.boolean().default(true),
});

const createSchema = z
  .object({
    name: z.string().trim().min(1).max(150),
    startsAt: z.string(),
    endsAt: z.string(),
    items: z.array(itemSchema).min(1).max(500),
    notifyCustomers: z.boolean().default(false),
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
    // Uniqueness — productId + variantId combo tidak boleh duplikat
    // dalam 1 promo (per-row).
    const seen = new Set<string>();
    for (const [idx, item] of data.items.entries()) {
      const key = `${item.productId}::${item.variantId ?? ""}`;
      if (seen.has(key)) {
        ctx.addIssue({
          code: "custom",
          message: "Produk/varian duplikat dalam satu promo",
          path: ["items", idx, "productId"],
        });
      }
      seen.add(key);
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
    include: {
      _count: { select: { items: true } },
    },
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

  // Conflict check: produk/varian yang sudah masuk Promo Toko aktif/
  // upcoming lain TIDAK BISA dipilih lagi.
  const now = new Date();
  const productKeys = body.items.map(
    (i) => `${i.productId}::${i.variantId ?? ""}`,
  );
  const productIds = Array.from(new Set(body.items.map((i) => i.productId)));
  const variantIds = body.items
    .map((i) => i.variantId)
    .filter((v): v is string => !!v);

  const conflictingItems = await prisma.productDiscountItem.findMany({
    where: {
      productId: { in: productIds },
      OR: variantIds.length > 0
        ? [
            { variantId: null },
            { variantId: { in: variantIds } },
          ]
        : [{ variantId: null }],
      discount: {
        isActive: true,
        endsAt: { gt: now },
      },
    },
    include: {
      discount: { select: { name: true } },
    },
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

  // Validate productId + variantId benar-benar ada di DB.
  const validProducts = await prisma.product.findMany({
    where: { id: { in: productIds } },
    select: { id: true },
  });
  if (validProducts.length !== productIds.length) {
    return NextResponse.json(
      { error: "Sebagian produk tidak ditemukan" },
      { status: 400 },
    );
  }
  if (variantIds.length > 0) {
    const validVariants = await prisma.productVariant.findMany({
      where: { id: { in: variantIds } },
      select: { id: true },
    });
    if (validVariants.length !== variantIds.length) {
      return NextResponse.json(
        { error: "Sebagian varian tidak ditemukan" },
        { status: 400 },
      );
    }
  }

  // Create discount + items atomically.
  const discount = await prisma.productDiscount.create({
    data: {
      name: body.name.trim(),
      startsAt: new Date(body.startsAt),
      endsAt: new Date(body.endsAt),
      isActive: true,
      notifyAtStart: body.notifyCustomers,
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

  // Suppress unused warning untuk productKeys (dipakai utk debug masa depan)
  void productKeys;

  // Kirim notif langsung bila dicentang & promo sudah aktif (startsAt <= now < endsAt).
  // Promo terjadwal (startsAt > now) diurus cron promo-notify.
  if (
    body.notifyCustomers &&
    discount.startsAt <= now &&
    discount.endsAt > now
  ) {
    after(() =>
      sendProductDiscountPromoPush(discount.id).catch((e) =>
        console.warn("[promo-toko-create] promo push:", e),
      ),
    );
  }

  return NextResponse.json(discount, { status: 201 });
}
