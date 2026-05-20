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
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
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

    const productIds = formData.getAll("productIds").map(String).filter(Boolean);
    const discountPercent = parseInt(
      String(formData.get("discountPercent") || "0"),
      10,
    );
    const endsAtRaw = String(formData.get("endsAt") || "").trim();
    const endsAt = endsAtRaw ? new Date(endsAtRaw) : null;

    if (productIds.length === 0 || !endsAt || endsAt <= new Date()) return;
    if (discountPercent < 1 || discountPercent > 95) return;

    // Update batch — hitung discountPrice dari current price × (1 - %)
    // per produk supaya tetap akurat per-item.
    const productsToUpdate = await prisma.product.findMany({
      where: { id: { in: productIds } },
      select: { id: true, price: true },
    });

    await Promise.all(
      productsToUpdate.map((p) =>
        prisma.product.update({
          where: { id: p.id },
          data: {
            discountPrice: Math.round(p.price * (1 - discountPercent / 100)),
            flashSaleEndsAt: endsAt,
          },
        }),
      ),
    );

    redirect("/admin/diskon");
  }

  return <FlashSaleNewForm products={products} action={createFlashSale} />;
}
