/**
 * Penyusun baris ekspor produk — gaya Shopee Seller Centre: produk
 * bervarian dipecah SATU BARIS PER VARIAN, produk tanpa varian satu baris.
 *
 * Murni (tanpa DB/exceljs) supaya bisa diuji: rute yang memanggil hanya
 * menuangkan hasil ini ke worksheet.
 *
 * Keputusan bentuk yang disengaja:
 * - Produk bervarian TIDAK punya baris induk terpisah — stok di baris induk
 *   selalu 0 (stok asli hidup per varian) dan baris 0 palsu itu persis yang
 *   menyesatkan stok opname.
 * - Harga diskon & harga member level PRODUK (skema tidak menyimpannya per
 *   varian) — di baris varian keduanya tetap ditampilkan apa adanya.
 * - Deskripsi sengaja TIDAK ikut: sel raksasa merusak lembar opname.
 */

export type ExportVariantOption = {
  value: string;
  attributeName: string;
  attributePosition: number;
};

export type ExportVariant = {
  sku: string | null;
  price: number;
  stock: number;
  weightGram: number;
  isActive: boolean;
  options: ExportVariantOption[];
};

export type ExportProduct = {
  name: string;
  slug: string;
  sku: string | null;
  brandName: string | null;
  categoryName: string | null;
  price: number;
  discountPrice: number | null;
  memberPrice: number | null;
  flashSaleEndsAt: Date | null;
  stock: number;
  weightGram: number;
  isActive: boolean;
  hasVariants: boolean;
  variants: ExportVariant[];
};

export type ExportRow = {
  nama: string;
  varian: string;
  skuProduk: string;
  skuVarian: string;
  brand: string;
  kategori: string;
  harga: number;
  hargaDiskon: number | null;
  hargaMember: number | null;
  stok: number;
  beratGram: number;
  status: string;
  flashSaleBerakhir: string;
  link: string;
};

export const EXPORT_COLUMNS: Array<{
  header: string;
  key: keyof ExportRow;
  width: number;
}> = [
  { header: "Nama Produk", key: "nama", width: 46 },
  { header: "Varian", key: "varian", width: 28 },
  { header: "SKU Produk", key: "skuProduk", width: 16 },
  { header: "SKU Varian", key: "skuVarian", width: 16 },
  { header: "Brand", key: "brand", width: 18 },
  { header: "Kategori", key: "kategori", width: 18 },
  { header: "Harga", key: "harga", width: 12 },
  { header: "Harga Diskon", key: "hargaDiskon", width: 12 },
  { header: "Harga Member", key: "hargaMember", width: 12 },
  { header: "Stok", key: "stok", width: 8 },
  { header: "Berat (gram)", key: "beratGram", width: 11 },
  { header: "Status", key: "status", width: 10 },
  { header: "Flash Sale Berakhir", key: "flashSaleBerakhir", width: 19 },
  { header: "Link", key: "link", width: 44 },
];

/** "Rasa: Salmon, Ukuran: 1KG" — urut mengikuti posisi atribut di admin. */
export function variantLabel(options: ExportVariantOption[]): string {
  return [...options]
    .sort((a, b) => a.attributePosition - b.attributePosition)
    .map((o) => `${o.attributeName}: ${o.value}`)
    .join(", ");
}

function baseRow(p: ExportProduct): Omit<
  ExportRow,
  "varian" | "skuVarian" | "harga" | "stok" | "beratGram" | "status"
> {
  return {
    nama: p.name,
    skuProduk: p.sku ?? "",
    brand: p.brandName ?? "",
    kategori: p.categoryName ?? "",
    hargaDiskon: p.discountPrice,
    hargaMember: p.memberPrice,
    flashSaleBerakhir: p.flashSaleEndsAt
      ? p.flashSaleEndsAt.toISOString().slice(0, 16).replace("T", " ")
      : "",
    link: `https://natalopetshop.com/products/${p.slug}`,
  };
}

function statusLabel(active: boolean): string {
  return active ? "Aktif" : "Nonaktif";
}

export function buildExportRows(products: ExportProduct[]): ExportRow[] {
  const rows: ExportRow[] = [];
  for (const p of products) {
    if (p.hasVariants && p.variants.length > 0) {
      for (const v of p.variants) {
        rows.push({
          ...baseRow(p),
          varian: variantLabel(v.options),
          skuVarian: v.sku ?? "",
          harga: v.price,
          stok: v.stock,
          beratGram: v.weightGram,
          // Varian nonaktif tetap diekspor (stok fisiknya bisa masih ada
          // di rak) tapi statusnya jujur; produk nonaktif menular ke
          // semua barisnya.
          status: statusLabel(p.isActive && v.isActive),
        });
      }
    } else {
      rows.push({
        ...baseRow(p),
        varian: "",
        skuVarian: "",
        harga: p.price,
        stok: p.stock,
        beratGram: p.weightGram,
        status: statusLabel(p.isActive),
      });
    }
  }
  return rows;
}
