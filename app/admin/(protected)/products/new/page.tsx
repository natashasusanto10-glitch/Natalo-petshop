/**
 * /admin/products/new — Tambah Produk
 *
 * Server component yang fetch categories + brands lalu render client
 * form (NewProductForm). Form sekarang full 1-page integration:
 * produk + varian disimpan atomically dalam 1 submit via POST
 * /api/admin/products.
 *
 * Field order (sesuai spec):
 *  1. Foto Produk → 2. Nama → 3. Kategori|Brand → 4. Deskripsi
 *  5. Variasi (VariantEditor draft mode)
 *  6. Harga Satuan → 7. Stok → 8. Berat
 *
 * Behavior conditional:
 *  - Varian OFF: Harga Satuan/Stok/Berat enabled + required
 *  - Varian ON: Harga Satuan/Stok/Berat disabled (data dari per-varian)
 */
import { prisma } from "@/lib/prisma";
import { NewProductForm } from "@/components/admin/NewProductForm";

export default async function AdminProductNewPage() {
  const [categories, brands] = await Promise.all([
    prisma.category.findMany({
      orderBy: { name: "asc" },
      select: { id: true, name: true },
    }),
    prisma.brand.findMany({
      orderBy: { name: "asc" },
      select: { id: true, name: true },
    }),
  ]);

  return <NewProductForm categories={categories} brands={brands} />;
}
