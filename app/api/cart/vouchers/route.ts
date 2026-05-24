/**
 * GET /api/cart/vouchers?subtotal=N
 *
 * Return daftar voucher member Natalo (sourceType=CUSTOMER) untuk user
 * login + cart subtotal saat ini.
 *
 * Logic visibility ada di `lib/voucher-list.ts` (single source of truth).
 *
 * Response shape:
 *   { available: VoucherListItem[], unavailable: VoucherListItem[] }
 *
 * Guest dapat 401 — tidak boleh lihat voucher member.
 *
 * SELLER_MANUAL voucher TIDAK pernah muncul di endpoint ini (rahasia,
 * harus di-validate via /api/cart/vouchers/validate-private).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { listUserVouchers } from "@/lib/voucher-list";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      {
        error: "LOGIN_REQUIRED",
        message: "Login dulu untuk melihat voucher member.",
      },
      { status: 401 },
    );
  }

  const subtotalRaw = request.nextUrl.searchParams.get("subtotal");
  const subtotal = Math.max(0, parseInt(subtotalRaw ?? "0", 10) || 0);

  const { items } = await listUserVouchers({
    userId: session.sub,
    subtotal,
  });

  return NextResponse.json({
    available: items.filter((it) => it.applicable),
    unavailable: items.filter((it) => !it.applicable),
  });
}
