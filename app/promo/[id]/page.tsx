/**
 * Web fallback untuk deep link https://natalo.id/promo/<id>.
 *
 * Dipakai saat user tap link natalo.id/promo/<id> tanpa app Natalo
 * ter-install. <id> = HomeBanner.id (admin-managed, /admin/banners) —
 * resolve linkType+linkValue ke href yang sama persis dengan yang
 * dipakai Flutter DeepLinkService._openPromoById (lib/home-banners.ts),
 * supaya web & app konsisten. Banner tidak ketemu / href kosong →
 * fallback ke katalog diskon.
 */
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { bannerLinkToHref } from "@/lib/home-banners";

const FALLBACK_HREF = "/products?diskon=1";

export default async function PromoShortLinkPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const banner = await prisma.homeBanner
    .findUnique({
      where: { id },
      select: { linkType: true, linkValue: true },
    })
    .catch(() => null);

  const href = banner
    ? bannerLinkToHref(banner.linkType, banner.linkValue)
    : null;

  redirect(href || FALLBACK_HREF);
}
