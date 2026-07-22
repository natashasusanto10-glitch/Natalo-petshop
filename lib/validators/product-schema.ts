import { z } from "zod";

// Schema: Create product (extended dari POST sederhana original — sekarang
// support gallery + opsional variants. Backwards compatible: caller lama
// tanpa gallery / variants tetap jalan.
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
});
