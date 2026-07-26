import { Prisma } from "@prisma/client";

/**
 * Pesan bentrok SKU yang menyebut SIAPA pemegangnya.
 *
 * Konteks: `sku` adalah @unique di level DB (Product & ProductVariant), dan
 * "hapus produk" di admin sebenarnya cuma `isActive: false` — baris + varian
 * + SKU-nya tetap ada. Akibatnya SKU bisa dipegang produk yang TIDAK terlihat
 * di katalog, dan pesan lama ("sudah digunakan oleh varian lain") membuat
 * admin buntu: tidak ada cara menemukan pemegangnya. Sebutkan nama + status
 * produknya supaya admin tahu harus memulihkan/mengedit produk yang mana.
 */
export async function describeVariantSkuConflict(
  tx: Prisma.TransactionClient,
  sku: string,
  currentProductId?: string,
): Promise<string | null> {
  const holder = await tx.productVariant.findFirst({
    where: { sku },
    select: {
      deletedAt: true,
      product: { select: { id: true, name: true, isActive: true } },
    },
  });
  if (!holder) return null;
  const p = holder.product;
  if (currentProductId && p.id === currentProductId) {
    // Varian lama produk INI sendiri (biasanya sisa soft-delete yang belum
    // membebaskan SKU). Setelah fix `sku: null` ini seharusnya tak terjadi
    // lagi untuk data baru, tapi data lama masih bisa memicu.
    return holder.deletedAt
      ? `Kode SKU "${sku}" masih dipegang varian lama produk ini yang sudah dihapus. Simpan ulang dengan kode lain, atau hubungi developer untuk membebaskan kode lama.`
      : `Kode SKU "${sku}" dipakai dua kali di produk ini. Tiap varian harus punya kode berbeda.`;
  }
  const status = holder.deletedAt
    ? "varian sudah dihapus"
    : p.isActive
      ? "aktif"
      : "diarsipkan";
  return `Kode SKU "${sku}" sudah dipakai varian produk "${p.name}" (${status}). Ganti kodenya, atau ubah SKU di produk tersebut.`;
}

/** Versi untuk SKU Induk (Product.sku). */
export async function describeProductSkuConflict(
  tx: Prisma.TransactionClient,
  sku: string,
  currentProductId?: string,
): Promise<string | null> {
  const holder = await tx.product.findFirst({
    where: { sku, ...(currentProductId ? { id: { not: currentProductId } } : {}) },
    select: { name: true, isActive: true },
  });
  if (!holder) return null;
  return `SKU Induk "${sku}" sudah dipakai produk "${holder.name}" (${holder.isActive ? "aktif" : "diarsipkan"}). Ganti kodenya, atau ubah SKU produk tersebut.`;
}
