import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import type { Prisma, VoucherKind } from "@prisma/client";

/**
 * GET /api/admin/vouchers
 *
 * List voucher dengan filter status. Dipakai flutter_admin voucher tab.
 *
 * Query:
 * - `status` — "active" | "expired" | "all" (default "active")
 * - `q` — search by code or name
 * - `limit` — default 50
 */
export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const status = sp.get("status") ?? "active";
  const q = sp.get("q")?.trim() ?? "";
  const limit = Math.min(Math.max(parseInt(sp.get("limit") ?? "50", 10), 1), 100);

  const where: Prisma.VoucherWhereInput = {
    // Hanya voucher publik (admin-created promo) — exclude voucher
    // per-user (BDAY, POIN claim) yang userId-nya populated.
    userId: null,
  };
  const now = new Date();
  if (status === "active") {
    where.isActive = true;
    where.OR = [
      { expiresAt: null },
      { expiresAt: { gt: now } },
    ];
  } else if (status === "expired") {
    where.OR = [
      { isActive: false },
      { expiresAt: { lt: now } },
    ];
  }
  if (q) {
    where.OR = [
      ...(where.OR ?? []),
      { code: { contains: q, mode: "insensitive" } },
      { name: { contains: q, mode: "insensitive" } },
    ];
  }

  const vouchers = await prisma.voucher.findMany({
    where,
    take: limit,
    orderBy: { createdAt: "desc" },
    select: {
      id: true,
      code: true,
      name: true,
      description: true,
      discountPercent: true,
      discountAmount: true,
      minimumOrder: true,
      maxUsage: true,
      usedCount: true,
      startsAt: true,
      expiresAt: true,
      isActive: true,
      kind: true,
      discountType: true,
    },
  });

  return NextResponse.json({ vouchers });
}

/**
 * POST /api/admin/vouchers
 *
 * Buat voucher baru. Dipakai flutter_admin form "Tambah Voucher".
 *
 * Body: {code, name?, description?, discountPercent?, discountAmount?,
 *        minimumOrder?, maxUsage?, expiresAt?, kind?}
 *
 * Validasi:
 * - Code unik (cek konflik dulu, return 409)
 * - Salah satu dari discountPercent atau discountAmount harus diisi
 */
export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => null)) as
    | {
        code?: string;
        name?: string;
        description?: string;
        discountPercent?: number;
        discountAmount?: number;
        maxDiscountAmount?: number;
        minimumOrder?: number;
        maxUsage?: number;
        expiresAt?: string;
        kind?: string;
      }
    | null;

  if (!body || typeof body.code !== "string" || !body.code.trim()) {
    return NextResponse.json(
      { error: "Kode voucher wajib diisi" },
      { status: 400 },
    );
  }

  const hasPercent =
    typeof body.discountPercent === "number" && body.discountPercent > 0;
  const hasAmount =
    typeof body.discountAmount === "number" && body.discountAmount > 0;

  if (!hasPercent && !hasAmount) {
    return NextResponse.json(
      { error: "Salah satu dari diskon % atau diskon Rp wajib diisi" },
      { status: 400 },
    );
  }

  const code = body.code.trim().toUpperCase();
  const existing = await prisma.voucher.findUnique({ where: { code } });
  if (existing) {
    return NextResponse.json(
      { error: `Kode ${code} sudah dipakai voucher lain` },
      { status: 409 },
    );
  }

  // Map kind string ke enum value (default PRODUCT_DISCOUNT untuk safety).
  const kindMap: Record<string, VoucherKind> = {
    PRODUCT_DISCOUNT: "PRODUCT_DISCOUNT",
    FREE_SHIPPING: "FREE_SHIPPING",
    LOYALTY_CLAIM: "LOYALTY_CLAIM",
    MANUAL_PRIVATE: "MANUAL_PRIVATE",
  };
  const kind: VoucherKind =
    body.kind && kindMap[body.kind] ? kindMap[body.kind] : "PRODUCT_DISCOUNT";

  const voucher = await prisma.voucher.create({
    data: {
      code,
      name: body.name?.trim() || null,
      description: body.description?.trim() || null,
      discountPercent: hasPercent ? Math.round(body.discountPercent!) : null,
      discountAmount: hasAmount ? Math.round(body.discountAmount!) : null,
      maxDiscountAmount:
        typeof body.maxDiscountAmount === "number"
          ? Math.round(body.maxDiscountAmount)
          : null,
      minimumOrder:
        typeof body.minimumOrder === "number"
          ? Math.round(body.minimumOrder)
          : 0,
      maxUsage:
        typeof body.maxUsage === "number" && body.maxUsage > 0
          ? Math.round(body.maxUsage)
          : null,
      expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
      isActive: true,
      kind,
      // Schema enum: PERCENTAGE (bukan PERCENT) + FIXED_AMOUNT.
      discountType: hasPercent ? "PERCENTAGE" : "FIXED_AMOUNT",
      type:
        kind === "FREE_SHIPPING"
          ? "PUBLIC_FREE_SHIPPING"
          : "PUBLIC_PRODUCT_DISCOUNT",
    },
    select: {
      id: true,
      code: true,
      name: true,
      discountPercent: true,
      discountAmount: true,
      minimumOrder: true,
      expiresAt: true,
      isActive: true,
    },
  });

  return NextResponse.json(voucher, { status: 201 });
}
