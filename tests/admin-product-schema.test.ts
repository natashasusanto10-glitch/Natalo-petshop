import { describe, expect, it } from "vitest";
import { createProductSchema } from "../lib/validators/product-schema";

// Bug device: buat produk baru dengan Brand="Tanpa brand" + SKU Induk kosong
// (kasus PALING UMUM, bukan edge case) selalu gagal "Payload tidak valid".
// Root cause: ProductForm.tsx kirim `categoryId || null` / `brandId || null`
// / `sku.trim() || null` — payload literal `null`, bukan `undefined`. Zod
// `.optional()` TANPA `.nullable()` menolak `null` (cuma terima undefined).
describe("createProductSchema — null vs undefined utk field opsional", () => {
  const basePayload = {
    name: "Scoop Pasir Kucing",
    description: "Deskripsi produk",
    price: 6000,
    stock: 24,
    weightGram: 100,
    imageUrls: ["https://cdn.example.com/scoop.jpg"],
  };

  it("menerima categoryId/brandId/sku bernilai null (persis payload ProductForm.tsx saat 'Tanpa brand' + SKU kosong)", () => {
    const result = createProductSchema.safeParse({
      ...basePayload,
      categoryId: null,
      brandId: null,
      sku: null,
    });
    expect(result.success).toBe(true);
  });

  it("tetap menerima undefined (payload lama/backward-compat)", () => {
    const result = createProductSchema.safeParse(basePayload);
    expect(result.success).toBe(true);
  });

  it("tetap menerima string kosong untuk sku (kombinasi .or(z.literal('')) tak rusak)", () => {
    const result = createProductSchema.safeParse({ ...basePayload, sku: "" });
    expect(result.success).toBe(true);
  });

  it("tetap menolak categoryId non-string yang bukan null (mis. angka)", () => {
    const result = createProductSchema.safeParse({
      ...basePayload,
      categoryId: 123,
    });
    expect(result.success).toBe(false);
  });
});
