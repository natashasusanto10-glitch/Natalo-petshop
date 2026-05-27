import { NextRequest, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

/**
 * PATCH /api/admin/vouchers/[id]
 *
 * Update voucher publik (toggle isActive, edit field). Dipakai
 * flutter_admin untuk edit + activate/deactivate.
 *
 * Hanya boleh edit voucher publik (userId = null) — voucher per-user
 * (BDAY, POIN claim, MANUAL_PRIVATE personal) tidak boleh disentuh
 * lewat admin app supaya tidak nge-bypass loyalty/claim logic.
 *
 * Body (semua opsional, partial update):
 *   - name, description
 *   - discountPercent | discountAmount (mutually exclusive; switch jenis
 *     diskon -> tulis salah satu, satunya di-null-kan otomatis)
 *   - minimumOrder, maxUsage (null = unlimited)
 *   - expiresAt (ISO string atau null)
 *   - isActive (toggle)
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await prisma.voucher.findUnique({
    where: { id },
    select: { id: true, userId: true, discountType: true },
  });
  if (!existing) {
    return NextResponse.json(
      { error: "Voucher tidak ditemukan" },
      { status: 404 },
    );
  }
  if (existing.userId !== null) {
    return NextResponse.json(
      { error: "Voucher per-user tidak bisa diedit via admin app" },
      { status: 403 },
    );
  }

  const body = (await request.json().catch(() => null)) as
    | {
        name?: string | null;
        description?: string | null;
        discountPercent?: number | null;
        discountAmount?: number | null;
        minimumOrder?: number;
        maxUsage?: number | null;
        expiresAt?: string | null;
        isActive?: boolean;
      }
    | null;

  if (!body) {
    return NextResponse.json({ error: "Body wajib" }, { status: 400 });
  }

  const data: Prisma.VoucherUpdateInput = {};

  if (typeof body.name === "string" || body.name === null) {
    data.name = body.name?.trim() || null;
  }
  if (typeof body.description === "string" || body.description === null) {
    data.description = body.description?.trim() || null;
  }

  // Diskon: kalau salah satu di-set, otomatis null-kan satunya supaya
  // tidak konflik dengan discountType. Kalau dua-duanya undefined,
  // jangan sentuh field discount sama sekali.
  const hasPercentField = "discountPercent" in body;
  const hasAmountField = "discountAmount" in body;
  if (hasPercentField || hasAmountField) {
    const percent =
      typeof body.discountPercent === "number" && body.discountPercent > 0
        ? Math.round(body.discountPercent)
        : null;
    const amount =
      typeof body.discountAmount === "number" && body.discountAmount > 0
        ? Math.round(body.discountAmount)
        : null;
    if (percent === null && amount === null) {
      return NextResponse.json(
        { error: "Diskon % atau Rp harus salah satu > 0" },
        { status: 400 },
      );
    }
    // Mutually exclusive — percent menang kalau dua-duanya dikirim.
    if (percent !== null) {
      data.discountPercent = percent;
      data.discountAmount = null;
      data.discountType = "PERCENTAGE";
    } else {
      data.discountAmount = amount;
      data.discountPercent = null;
      data.discountType = "FIXED_AMOUNT";
    }
  }

  if (typeof body.minimumOrder === "number") {
    data.minimumOrder = Math.max(0, Math.round(body.minimumOrder));
  }

  if ("maxUsage" in body) {
    data.maxUsage =
      typeof body.maxUsage === "number" && body.maxUsage > 0
        ? Math.round(body.maxUsage)
        : null;
  }

  if ("expiresAt" in body) {
    if (body.expiresAt === null || body.expiresAt === "") {
      data.expiresAt = null;
    } else if (typeof body.expiresAt === "string") {
      const d = new Date(body.expiresAt);
      if (Number.isNaN(d.getTime())) {
        return NextResponse.json(
          { error: "Format tanggal berakhir tidak valid" },
          { status: 400 },
        );
      }
      data.expiresAt = d;
    }
  }

  if (typeof body.isActive === "boolean") {
    data.isActive = body.isActive;
  }

  if (Object.keys(data).length === 0) {
    return NextResponse.json(
      { error: "Tidak ada field yang diubah" },
      { status: 400 },
    );
  }

  const updated = await prisma.voucher.update({
    where: { id },
    data,
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
      expiresAt: true,
      isActive: true,
      kind: true,
      discountType: true,
    },
  });

  return NextResponse.json(updated);
}

/**
 * DELETE /api/admin/vouchers/[id]
 *
 * Hapus voucher publik. Sama dengan PATCH — voucher per-user di-block
 * supaya tidak nge-rusak loyalty/claim history.
 *
 * Voucher yang sudah pernah dipakai (usedCount > 0) di-soft-delete
 * (set isActive=false) karena VoucherUsage row punya FK ke Voucher;
 * hapus hard akan cascade hapus history pemakaian, dan itu bisa
 * meng-hilangkan jejak audit untuk dispute order/refund. Voucher
 * baru (usedCount=0) di-hard-delete supaya benar-benar bersih.
 */
export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const existing = await prisma.voucher.findUnique({
    where: { id },
    select: { id: true, userId: true, usedCount: true },
  });
  if (!existing) {
    return NextResponse.json(
      { error: "Voucher tidak ditemukan" },
      { status: 404 },
    );
  }
  if (existing.userId !== null) {
    return NextResponse.json(
      { error: "Voucher per-user tidak bisa dihapus via admin app" },
      { status: 403 },
    );
  }

  if (existing.usedCount > 0) {
    await prisma.voucher.update({
      where: { id },
      data: { isActive: false },
    });
    return NextResponse.json({
      ok: true,
      mode: "soft",
      message: "Voucher di-nonaktifkan (sudah ada history pemakaian).",
    });
  }

  await prisma.voucher.delete({ where: { id } });
  return NextResponse.json({ ok: true, mode: "hard" });
}
