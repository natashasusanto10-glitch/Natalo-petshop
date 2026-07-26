import { z } from "zod";
import { formatFieldErrors } from "./format-errors";

// Label Indonesia per field, dipakai untuk mengubah `flatten().fieldErrors`
// jadi pesan yang bisa dibaca admin. TANPA ini, 14+ penyebab berbeda (nama
// kepanjangan, harga NaN, slot foto null, SKU ada spasi, dll.) semuanya
// tampil sebagai "Payload tidak valid" — admin tidak punya petunjuk apa pun
// dan cuma bisa tebak-tebakan.
const FIELD_LABELS: Record<string, string> = {
  name: "Nama Produk",
  description: "Deskripsi",
  price: "Harga Satuan",
  stock: "Stok",
  weightGram: "Berat (gram)",
  imageUrl: "Foto cover",
  imageUrls: "Foto Produk",
  gallery: "Galeri foto",
  categoryId: "Kategori",
  brandId: "Brand",
  isActive: "Status aktif",
  sku: "SKU Induk",
  hasVariants: "Mode varian",
  attributes: "Atribut varian",
  variants: "Daftar varian",
  video: "Video produk",
  careCategory: "Kategori Obat",
  targetSpecies: "Spesies target",
  dosageRules: "Aturan dosis",
};

/**
 * Ubah `zodError.flatten().fieldErrors` jadi satu pesan siap-tampil.
 *
 * Contoh hasil: `Nama Produk: maksimal 200 karakter. Foto Produk: ada nilai
 * kosong yang belum terisi.`
 */
export function formatProductFieldErrors(
  fieldErrors: Record<string, string[] | undefined>,
  formErrors: string[] = [],
): string {
  return formatFieldErrors(fieldErrors, FIELD_LABELS, formErrors, "Ada data produk yang belum valid.");
}

export const createProductSchema = z.object({
  name: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).optional().default(""),
  price: z.number().int().min(0).max(999_999_999),
  stock: z.number().int().min(0).max(999_999).optional().default(0),
  weightGram: z.number().int().min(1).max(999_999).optional().default(500),
  imageUrl: z.string().trim().optional(),
  imageUrls: z.array(z.string().trim()).max(9).optional(),
  // Maksimal 9 foto total: 1 cover (imageUrl) + 8 gallery.
  gallery: z.array(z.string().trim()).max(8).optional().default([]),
  // .nullable() WAJIB — ProductForm.tsx kirim `categoryId || null` /
  // `brandId || null` saat "Tanpa kategori"/"Tanpa brand" dipilih (payload
  // asli, bukan undefined). Tanpa .nullable(), Zod .optional() cuma terima
  // undefined → null ditolak → seluruh create GAGAL "Payload tidak valid"
  // untuk kasus PALING UMUM (produk tanpa brand). normalizeProductFormPayload
  // + tipe ProductFormPayload (lib/product/admin-product-form.ts) SUDAH
  // didesain terima `string | null` — cuma gerbang Zod ini yang belum sinkron.
  categoryId: z.string().trim().optional().nullable(),
  brandId: z.string().trim().optional().nullable(),
  isActive: z.boolean().optional().default(true),
  // SKU Induk — opsional, identifier produk single (tanpa varian). .nullable()
  // WAJIB dengan alasan sama: ProductForm.tsx kirim `sku.trim() || null` saat
  // field SKU Induk dikosongkan (kasus paling umum juga).
  // Validasi: huruf/angka/_/- saja (consistent dengan ProductVariant.sku).
  sku: z
    .string()
    .trim()
    .max(80)
    .regex(/^[A-Za-z0-9_\-]+$/, "SKU Induk hanya boleh huruf, angka, _ dan -")
    .optional()
    .nullable()
    .or(z.literal("")),
  // Variant payload optional. Kalau ada + hasVariants=true, varian
  // di-create dalam transaction yang sama. Reuse validator dari
  // putVariantsPayloadSchema (sub-set untuk struktur attribute+variant).
  hasVariants: z.boolean().optional().default(false),
  attributes: z.array(z.any()).optional().default([]),
  variants: z.array(z.any()).optional().default([]),
  video: z
    .object({
      guid: z.string().optional(),
      url: z.string().optional(),
      status: z.string().optional(),
    })
    .nullable()
    .optional(),
  // Obat cacing/kutu — Task 9. careCategory null/"" berarti bukan obat;
  // targetSpecies+dosageRules divalidasi manual di route (bukan di sini)
  // supaya pesan error lebih spesifik dan konsisten dengan PATCH route.
  careCategory: z.string().trim().max(20).optional().nullable(),
  targetSpecies: z.array(z.string()).optional(),
  dosageRules: z.array(z.any()).optional().nullable(),
});
