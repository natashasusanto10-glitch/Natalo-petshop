/**
 * Web fallback untuk deep link https://natalo.id/brand/<slug>.
 *
 * Dipakai saat user tap link natalo.id/brand/<slug> tanpa app Natalo
 * ter-install. /products?brand=<slug> sudah support filter brand by slug
 * (lihat app/products/page.tsx), jadi redirect langsung ke situ tanpa
 * perlu halaman brand terpisah.
 */
import { redirect } from "next/navigation";

export default async function BrandShortLinkPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  redirect(`/products?brand=${encodeURIComponent(slug)}`);
}
