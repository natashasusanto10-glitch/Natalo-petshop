/**
 * POST /api/admin/products/reset
 *
 * Reset semua produk dari database production. Pemanggil HARUS mengirim
 * { confirm: "HAPUS" } persis — guard sederhana agar tidak ke-trigger
 * tidak sengaja.
 *
 * Modes:
 *   - Default (wipeOrders=false):
 *       1. Produk dengan OrderItem → SOFT ARCHIVE (isActive=false, stock=0)
 *       2. Produk tanpa OrderItem → HARD DELETE (cascade ke varian/review/wishlist)
 *       3. Clear semua CartItem (no FK)
 *
 *   - wipeOrders=true (full reset, untuk dev/testing):
 *       1. Delete semua Order. Cascade DB akan hapus:
 *          - OrderItem (cascade dari Order)
 *          - Review (cascade dari OrderItem via orderItemId)
 *          - ReviewVote / ReviewReply (cascade dari Review)
 *       2. Setelah orders kosong, SEMUA produk bisa di-hard-delete tanpa
 *          FK violation.
 *       3. Clear semua CartItem.
 *
 * Setelah reset, halaman /products & /produk di-revalidate.
 */
import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";

// Beri timeout lebih untuk eksekusi cascade delete pada dataset besar.
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  // Defense-in-depth: production butuh env flag ALLOW_DESTRUCTIVE_RESET=true
  // untuk arm endpoint ini. Tanpa flag, walau admin cookie dicuri, endpoint
  // tetap return 503. Set flag sementara untuk maintenance window, lalu
  // hapus lagi setelah selesai.
  if (
    process.env.NODE_ENV === "production" &&
    process.env.ALLOW_DESTRUCTIVE_RESET !== "true"
  ) {
    return NextResponse.json(
      {
        error:
          "Reset endpoint disabled di production. Admin set ALLOW_DESTRUCTIVE_RESET=true di Vercel untuk enable sementara.",
      },
      { status: 503 },
    );
  }

  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    confirm?: string;
    wipeOrders?: boolean;
    wipeTaxonomy?: boolean;
  };
  if (body.confirm !== "HAPUS") {
    return NextResponse.json(
      { error: 'Konfirmasi tidak valid. Kirim { confirm: "HAPUS" }.' },
      { status: 400 },
    );
  }

  const wipeOrders = body.wipeOrders === true;
  const wipeTaxonomy = body.wipeTaxonomy === true;

  // Snapshot count sebelum reset.
  const totalBefore = await prisma.product.count();

  // ── Mode wipeOrders: hapus dulu seluruh order data ─────────────
  let ordersDeleted = 0;
  if (wipeOrders) {
    const orderResult = await prisma.order.deleteMany({});
    ordersDeleted = orderResult.count;
    // Setelah orders kosong, OrderItem otomatis kehapus via cascade,
    // Review → ReviewVote/ReviewReply juga ikut. Jadi sekarang tidak ada
    // FK constraint dari product side.
  }

  // 1. Cari productId yang masih dipakai di OrderItem (kalau wipeOrders=true,
  //    list ini akan kosong).
  const orderedProductRows = await prisma.orderItem.findMany({
    select: { productId: true },
    distinct: ["productId"],
  });
  const protectedIds = orderedProductRows.map((row) => row.productId);

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

  // 4. Hard delete produk yang tidak protected. Cascade DB hapus
  //    VariantAttribute, VariantOption, ProductVariant,
  //    ProductVariantOption, Review, Favorite.
  const deleteResult = await prisma.product.deleteMany({
    where: protectedIds.length > 0 ? { id: { notIn: protectedIds } } : {},
  });

  // 5. Optional: hapus semua Category & Brand.
  //    CATATAN: Komentar lama keliru — Product.brand/category TIDAK
  //    pakai onDelete: SetNull (defaultnya Restrict di Prisma). Selama
  //    masih ada Product apapun (termasuk yang ARCHIVE dgn isActive=false)
  //    yang refer brandId/categoryId, brand.deleteMany & category.deleteMany
  //    akan throw FK constraint → reset gagal silent (brandsDeleted=0).
  //    Pre-null brandId & categoryId di semua produk tersisa supaya bebas
  //    dari FK lalu hapus brand/category aman.
  let categoriesDeleted = 0;
  let brandsDeleted = 0;
  let productsBrandNulled = 0;
  let productsCategoryNulled = 0;
  if (wipeTaxonomy) {
    // Null-kan FK di SEMUA produk tersisa (termasuk archive). Tanpa filter
    // — terlalu defensif tapi murah (cuma update int, dan kebanyakan case
    // produk sudah ke-delete sebelumnya jadi count 0).
    const brandNullResult = await prisma.product.updateMany({
      where: { brandId: { not: null } },
      data: { brandId: null },
    });
    productsBrandNulled = brandNullResult.count;
    const catNullResult = await prisma.product.updateMany({
      where: { categoryId: { not: null } },
      data: { categoryId: null },
    });
    productsCategoryNulled = catNullResult.count;

    const catResult = await prisma.category.deleteMany({});
    const brandResult = await prisma.brand.deleteMany({});
    categoriesDeleted = catResult.count;
    brandsDeleted = brandResult.count;
  }

  const remainingProducts = await prisma.product.count();
  const remainingCategories = await prisma.category.count();
  const remainingBrands = await prisma.brand.count();

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
      ordersDeleted,
      categoriesDeleted,
      brandsDeleted,
      // Jumlah produk yang brandId/categoryId-nya di-null-kan sebelum
      // hapus taxonomy. Diagnostic: kalau ini > 0 berarti ada produk
      // yang gagal di-delete sebelumnya (mis. ARCHIVE) — sekarang
      // FK-nya di-clear supaya brand/category bisa di-wipe.
      productsBrandNulled,
      productsCategoryNulled,
      remainingCategories,
      remainingBrands,
    },
  });
}
