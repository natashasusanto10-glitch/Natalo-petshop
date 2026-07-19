/**
 * Cron promo-notify — jalan tiap jam. Kirim notifikasi promo (voucher +
 * Promo Toko) yang dijadwalkan mulai di masa depan (notifyAtStart=true,
 * belum ter-notif) begitu waktu mulai tercapai. Promo yang aktif saat dibuat
 * sudah dikirim langsung dari server action / POST route; cron ini backstop
 * untuk yang terjadwal.
 *
 * Idempotensi dijamin klaim atomik di dalam sendVoucherPromoPush /
 * sendProductDiscountPromoPush (updateMany where promoNotifiedAt null).
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  sendVoucherPromoPush,
  sendProductDiscountPromoPush,
} from "@/lib/push-promo";

const LIMIT = 20;

export async function GET(request: NextRequest) {
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret) {
    const auth = request.headers.get("authorization");
    if (auth !== `Bearer ${cronSecret}`) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
  }

  const now = new Date();

  const vouchers = await prisma.voucher.findMany({
    where: {
      notifyAtStart: true,
      promoNotifiedAt: null,
      isActive: true,
      startsAt: { lte: now },
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    },
    select: { id: true },
    take: LIMIT,
  });

  const discounts = await prisma.productDiscount.findMany({
    where: {
      notifyAtStart: true,
      promoNotifiedAt: null,
      isActive: true,
      startsAt: { lte: now },
      endsAt: { gt: now },
    },
    select: { id: true },
    take: LIMIT,
  });

  for (const v of vouchers) await sendVoucherPromoPush(v.id);
  for (const d of discounts) await sendProductDiscountPromoPush(d.id);

  return NextResponse.json({
    ok: true,
    vouchers: vouchers.length,
    discounts: discounts.length,
  });
}
