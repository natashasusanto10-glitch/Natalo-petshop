import { z } from "zod";

const MAX_ATTRIBUTES = 3;
const MAX_OPTIONS_PER_ATTRIBUTE = 30;
const MAX_VARIANTS = 200;
const MAX_NAME_LENGTH = 60;
const MAX_SKU_LENGTH = 80;
const MAX_IMAGE_URL_LENGTH = 500;

const optionSchema = z.object({
  value: z.string().trim().min(1).max(MAX_NAME_LENGTH),
  position: z.number().int().min(0).max(MAX_OPTIONS_PER_ATTRIBUTE - 1),
});

const attributeSchema = z.object({
  name: z.string().trim().min(1).max(MAX_NAME_LENGTH),
  position: z.number().int().min(0).max(MAX_ATTRIBUTES - 1),
  options: z.array(optionSchema).min(1).max(MAX_OPTIONS_PER_ATTRIBUTE),
});

const variantSchema = z.object({
  optionRefs: z.array(z.string().trim().min(1)).min(1).max(MAX_ATTRIBUTES),
  price: z.number().int().min(0).max(999_999_999),
  stock: z.number().int().min(0).max(999_999),
  weightGram: z.number().int().min(0).max(999_999),
  sku: z
    .string()
    .trim()
    .max(MAX_SKU_LENGTH)
    .regex(/^[A-Za-z0-9_\-]+$/, "SKU hanya boleh mengandung huruf, angka, _ dan -")
    .optional(),
  imageUrl: z.string().trim().max(MAX_IMAGE_URL_LENGTH).optional(),
  isActive: z.boolean().default(true),
});

export const putVariantsPayloadSchema = z
  .object({
    hasVariants: z.boolean(),
    attributes: z.array(attributeSchema).max(MAX_ATTRIBUTES),
    variants: z.array(variantSchema).max(MAX_VARIANTS),
  })
  .superRefine((data, ctx) => {
    if (!data.hasVariants) return;

    if (data.attributes.length === 0) {
      ctx.addIssue({
        code: "custom",
        path: ["attributes"],
        message: "Minimal satu atribut varian wajib diisi.",
      });
    }

    if (data.variants.length === 0) {
      ctx.addIssue({
        code: "custom",
        path: ["variants"],
        message: "Minimal satu varian wajib diisi.",
      });
    }

    const attrPositions = new Set<number>();
    const validOptionRefs = new Set<string>();
    for (const [attrIndex, attr] of data.attributes.entries()) {
      if (attrPositions.has(attr.position)) {
        ctx.addIssue({
          code: "custom",
          path: ["attributes", attrIndex, "position"],
          message: "Posisi atribut tidak boleh duplikat.",
        });
      }
      attrPositions.add(attr.position);

      const optionValues = new Set<string>();
      const optionPositions = new Set<number>();
      for (const [optionIndex, option] of attr.options.entries()) {
        const normalizedValue = option.value.toLowerCase();
        if (optionValues.has(normalizedValue)) {
          ctx.addIssue({
            code: "custom",
            path: ["attributes", attrIndex, "options", optionIndex, "value"],
            message: "Opsi dalam satu atribut tidak boleh duplikat.",
          });
        }
        optionValues.add(normalizedValue);

        if (optionPositions.has(option.position)) {
          ctx.addIssue({
            code: "custom",
            path: ["attributes", attrIndex, "options", optionIndex, "position"],
            message: "Posisi opsi tidak boleh duplikat.",
          });
        }
        optionPositions.add(option.position);
        validOptionRefs.add(`${attr.position}:${option.value}`);
      }
    }

    const skuSet = new Set<string>();
    const combinationSet = new Set<string>();
    let activeVariantCount = 0;
    for (const [variantIndex, variant] of data.variants.entries()) {
      if (variant.isActive) {
        activeVariantCount += 1;
        if (variant.price <= 0) {
          ctx.addIssue({
            code: "custom",
            path: ["variants", variantIndex, "price"],
            message: "Varian aktif harus punya harga lebih dari 0.",
          });
        }
        if (variant.weightGram <= 0) {
          ctx.addIssue({
            code: "custom",
            path: ["variants", variantIndex, "weightGram"],
            message: "Varian aktif harus punya berat lebih dari 0.",
          });
        }
      }

      const refs = new Set(variant.optionRefs);
      if (refs.size !== variant.optionRefs.length) {
        ctx.addIssue({
          code: "custom",
          path: ["variants", variantIndex, "optionRefs"],
          message: "Option ref dalam satu varian tidak boleh duplikat.",
        });
      }

      for (const ref of variant.optionRefs) {
        if (!validOptionRefs.has(ref)) {
          ctx.addIssue({
            code: "custom",
            path: ["variants", variantIndex, "optionRefs"],
            message: `Option ref "${ref}" tidak valid.`,
          });
        }
      }

      if (variant.optionRefs.length !== data.attributes.length) {
        ctx.addIssue({
          code: "custom",
          path: ["variants", variantIndex, "optionRefs"],
          message: "Setiap varian harus memilih satu opsi dari tiap atribut.",
        });
      }

      const combinationKey = [...refs].sort().join("|");
      if (combinationSet.has(combinationKey)) {
        ctx.addIssue({
          code: "custom",
          path: ["variants", variantIndex, "optionRefs"],
          message: "Kombinasi varian tidak boleh duplikat.",
        });
      }
      combinationSet.add(combinationKey);

      const sku = variant.sku?.trim();
      if (sku) {
        const normalizedSku = sku.toLowerCase();
        if (skuSet.has(normalizedSku)) {
          ctx.addIssue({
            code: "custom",
            path: ["variants", variantIndex, "sku"],
            message: "SKU tidak boleh duplikat.",
          });
        }
        skuSet.add(normalizedSku);
      }
    }

    if (activeVariantCount === 0) {
      ctx.addIssue({
        code: "custom",
        path: ["variants"],
        message: "Minimal satu varian harus aktif.",
      });
    }
  });

export type PutVariantsPayload = z.infer<typeof putVariantsPayloadSchema>;

const VARIANT_FIELD_LABELS: Record<string, string> = {
  sku: "Kode SKU",
  price: "Harga",
  stock: "Stok",
  weightGram: "Berat",
  imageUrl: "Foto varian",
  isActive: "Status aktif",
  optionRefs: "Opsi/kombinasi",
  value: "Nama opsi",
  position: "Urutan",
  name: "Nama atribut",
  options: "Daftar opsi",
};

/**
 * Ubah issues Zod (termasuk custom path dari superRefine) jadi pesan yang
 * menyebut BARIS dan FIELD-nya, mis. `Varian #3 — Harga: Varian aktif harus
 * punya harga lebih dari 0.`
 *
 * Dipakai menggantikan "Payload varian tidak valid" — string itu tidak
 * memberi tahu admin baris varian mana yang bermasalah, padahal satu produk
 * bisa punya sampai 200 varian.
 */
export function formatVariantIssues(
  issues: Array<{ path: Array<string | number | symbol>; message: string }>,
): string {
  if (issues.length === 0) return "Ada data varian yang belum valid.";
  const described = issues.slice(0, 3).map((issue) => {
    const [root, index, field] = issue.path;
    const rootLabel = root === "attributes" ? "Atribut" : root === "variants" ? "Varian" : "";
    const where = typeof index === "number" ? `${rootLabel} #${index + 1}` : rootLabel;
    const fieldLabel = typeof field === "string" ? VARIANT_FIELD_LABELS[field] ?? field : "";
    const prefix = [where, fieldLabel].filter(Boolean).join(" — ");
    return prefix ? `${prefix}: ${issue.message}` : issue.message;
  });
  const sisa = issues.length - described.length;
  return described.join(". ") + (sisa > 0 ? ` (dan ${sisa} masalah lain)` : "");
}
