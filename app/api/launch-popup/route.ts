/**
 * GET /api/launch-popup
 *
 * Return popup promo bergambar untuk cold start app Flutter (gaya Shopee:
 * satu gambar kreatif penuh + tombol X). Admin kelola via /admin/launch-popup.
 *
 * Response: { popup: { id, image, imageAlt, href, audience } | null }
 * - popup null = tidak ada popup aktif → app tidak menampilkan apa-apa.
 * - Filter jadwal (startsAt/endsAt) di server supaya Flutter tidak perlu
 *   compute time window — sama dengan pola /api/banners.
 * - href hasil bannerLinkToHref (semantik linkType SAMA dengan HomeBanner).
 * - audience: "all" | "member" — gating login dilakukan di sisi app
 *   (server tidak tahu auth state app saat fetch anonim).
 *
 * Cache pendek (60s) — popup promo harus responsif saat admin ganti gambar,
 * beda dengan banner yang 300s.
 */
import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { bannerLinkToHref } from "@/lib/home-banners";

export const revalidate = 60;

export async function GET() {
  try {
    const now = new Date();
    const popup = await prisma.launchPopup.findFirst({
      where: {
        isActive: true,
        OR: [{ startsAt: null }, { startsAt: { lte: now } }],
        AND: [{ OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
      },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        imageUrl: true,
        imageAlt: true,
        linkType: true,
        linkValue: true,
        audience: true,
      },
    });

    return NextResponse.json(
      {
        popup: popup
          ? {
              id: popup.id,
              image: popup.imageUrl,
              imageAlt: popup.imageAlt,
              href: bannerLinkToHref(popup.linkType, popup.linkValue),
              audience: popup.audience,
            }
          : null,
      },
      {
        headers: {
          "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
        },
      },
    );
  } catch {
    // DB error / tabel belum termigrasi → app fallback: tidak tampil popup.
    return NextResponse.json({ popup: null });
  }
}
