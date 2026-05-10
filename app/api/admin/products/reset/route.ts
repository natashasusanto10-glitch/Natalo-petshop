/**
 * POST /api/admin/products/reset
 *
 * Reset semua produk dari database production. Pemanggil HARUS mengirim
 * { confirm: "HAPUS" } persis — guard sederhana agar tidak ke-trigger
 * tidak sengaja.
 *
 * Strategi:
 *   1. Identifikasi produk yang punya OrderItem (history pesanan).
 *   2. Produk dengan history → SOFT ARCHIVE (isActive=false, stock=0,
 *      varian juga). Tidak dihapus karena OrderItem.product FK tanpa
 *      cascade — kalau di-hard-delete akan FK violation, dan history
 *      pesanan akan hilang.
 *   3. Produk tanpa history → HARD DELETE. DB cascade akan otomatis
 *      hapus VariantAttribute, VariantOption, ProductVariant,
 *      ProductVariantOption, Review, Favorite.
 *   4. CartItem (tidak ada FK ke Product) → clear semua, biar tidak
 *      ada orphan reference.
 *
 * Setelah reset, halaman /products & /produk di-revalidate.
 */
import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

// Beri timeout lebih untuk eksekusi cascade delete pada dataset besar.
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    confirm?: string;
  };
  if (body.confirm !== "HAPUS") {
    return NextResponse.json(
      { error: 'Konfirmasi tidak valid. Kirim { confirm: "HAPUS" }.' },
      { status: 400 },
    );
  }

  // Hitung dulu jumlah produk total — supaya bisa dilaporkan ke client.
  const totalBefore = await prisma.product.count();

  // 1. Cari semua productId yang muncul di OrderItem.
  const orderedProductRows = await prisma.orderItem.findMany({
    select: { productId: true },
    distinct: ["productId"],
  });
  const protectedIds = orderedProductRows.map((row) => row.productId);
  const protectedSet = new Set(protectedIds);

  // 2. Soft-archive produk dengan history pesanan + varian-nya.
  let archivedCount = 0;
  if (protectedIds.length > 0) {
    const archive = await prisma.product.updateMany({
      where: { id: { in: protectedIds } },
      data: { isActive: false, stock: 0 },
    });
    archivedCount = archive.count;
    await prisma.productVariant.updateMany({
      where: { productId: { in: protectedIds } },
      data: { isActive: false, stock: 0 },
    });
  }

  // 3. Clear semua CartItem (tidak ada FK constraint, tapi kita bersihkan
  //    agar tidak ada keranjang user yang refer produk hilang).
  const cartCleared = await prisma.cartItem.deleteMany({});

  // 4. Hard delete produk tanpa pesanan (DB cascade hapus relasi child).
  const deleteResult = await prisma.product.deleteMany({
    where: protectedSet.size > 0 ? { id: { notIn: protectedIds } } : {},
  });

  // 5. Bersihkan kategori & brand "yatim" (opsional — kategori/brand tanpa
  //    produk aktif). Kita TIDAK delete; cuma laporkan jumlahnya. Kategori
  //    & brand di-keep agar struktur tetap untuk import berikutnya.
  const remainingProducts = await prisma.product.count();

  revalidatePath("/products");
  revalidatePath("/produk");

  return NextResponse.json({
    ok: true,
    summary: {
      totalBefore,
      archived: archivedCount,
      deleted: deleteResult.count,
      remaining: remainingProducts,
      cartItemsCleared: cartCleared.count,
    },
  });
}
