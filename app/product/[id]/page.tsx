/**
 * Web fallback untuk deep link https://natalo.id/product/<id>.
 *
 * Dipakai saat user tap link natalo.id/product/<id> tanpa app Natalo
 * ter-install (App Links/Universal Links gagal verify, atau desktop
 * browser) — OS buka ini di browser biasa. getProductBySlug sudah
 * fallback slug→id (lib/products.ts), jadi redirect langsung ke halaman
 * produk existing di /products/<id> tanpa perlu duplikasi UI.
 */
import { redirect } from "next/navigation";

export default async function ProductShortLinkPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  redirect(`/products/${encodeURIComponent(id)}`);
}
