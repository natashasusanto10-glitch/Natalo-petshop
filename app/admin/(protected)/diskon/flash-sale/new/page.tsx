/**
 * /admin/diskon/flash-sale/new — Form Flash Sale baru.
 *
 * Server wrapper: load eligible products + define server action,
 * render FlashSaleNewForm (client) yang handle search + multi-select.
 *
 * Mekanisme: pilih 1 atau lebih produk → set harga flash (discountPrice)
 * + waktu berakhir (flashSaleEndsAt). Pakai field existing di Product
 * model (Opsi A — tidak buat model FlashSale baru).
 */
import { revalidatePath } from "next/cache";
import { syncProductsToSearchIndex } from "@/lib/search";
import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { FlashSaleNewForm } from "@/components/admin/FlashSaleNewForm";

export const dynamic = "force-dynamic";

export default async function FlashSaleNewPage() {
  // Ambil daftar produk untuk multi-select. Filter hanya yang aktif
  // + tidak sedang di flash sale lain (flashSaleEndsAt null atau expired).
  // Take 500 supaya client-side search bisa filter banyak produk.
  const now = new Date();
  // Bump take 500 → 2000 supaya semua produk eligible muat di picker
  // (limit teknis: client-side filter handle banyak data dengan baik).
  // Kalau di masa depan produk > 2000, perlu pagination + server-search.
  const products = await prisma.product.findMany({
    where: {
      isActive: true,
      OR: [
        { flashSaleEndsAt: null },
        { flashSaleEndsAt: { lt: now } },
      ],
    },
    orderBy: { name: "asc" },
    take: 2000,
    select: {
      id: true,
      name: true,
      price: true,
      imageUrl: true,
      slug: true,
    },
  });

  async function createFlashSale(formData: FormData) {
    "use server";
    await requireAdminSession();

    const productIds = [...new Set(formData.getAll("productIds").map(String).filter(Boolean))];
    const discountPercent = Number(formData.get("discountPercent"));
    const raw = String(formData.get("endsAt") || "");
    const endsAt = new Date(raw ? raw + ":00+07:00" : "");
    if (!productIds.length || productIds.length > 2000) return { error: "Pilih 1–2.000 produk." };
    if (!Number.isInteger(discountPercent) || discountPercent < 1 || discountPercent > 95) return { error: "Diskon harus 1–95%." };
    if (!Number.isFinite(endsAt.getTime()) || endsAt <= new Date()) return { error: "Waktu akhir harus setelah waktu sekarang (WIB)." };
    try {
      await prisma.$transaction(async (tx) => {
        const eligible = await tx.product.findMany({
          where: { id: { in: productIds }, isActive: true, OR: [{ flashSaleEndsAt: null }, { flashSaleEndsAt: { lte: new Date() } }] },
          select: { id: true, price: true },
        });
        if (eligible.length !== productIds.length) throw new Error("eligibility");
        for (const product of eligible) await tx.product.update({
          where: { id: product.id },
          data: { discountPrice: Math.round(product.price * (1 - discountPercent / 100)), flashSaleEndsAt: endsAt },
        });
      }, { isolationLevel: "Serializable", timeout: 30000 });
    } catch {
      return { error: "Flash Sale belum tersimpan. Pilihan produk mungkin berubah atau layanan sedang sibuk. Muat ulang dan coba lagi." };
    }
    try { await syncProductsToSearchIndex(productIds); } catch (error) { console.error("Flash Sale search sync failed", error); }
    revalidatePath("/admin/diskon"); revalidatePath("/admin/products"); revalidatePath("/", "layout");
    return { success: true };

  }

  return <FlashSaleNewForm products={products} action={createFlashSale} />;
}
