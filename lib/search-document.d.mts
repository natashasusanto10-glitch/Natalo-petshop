import type { ProductSearchDoc } from "./search";

export const SEARCHABLE_ATTRIBUTES: string[];
export const FILTERABLE_ATTRIBUTES: string[];
export const SORTABLE_ATTRIBUTES: string[];
export const SYNONYMS: Record<string, string[]>;
export const TYPO_TOLERANCE: {
  enabled: boolean;
  minWordSizeForTypos: { oneTypo: number; twoTypos: number };
};

export function productToSearchDoc(product: {
  id: string;
  slug: string;
  name: string;
  description?: string | null;
  categoryId: string | null;
  category?: { slug: string; name: string } | null;
  brandId: string | null;
  brand?: { slug: string; name: string } | null;
  price: number;
  discountPrice?: number | null;
  stock: number;
  weightGram: number;
  avgRating: number;
  reviewCount: number;
  createdAt: Date;
  imageUrl?: string | null;
  isActive: boolean;
  hasVariants: boolean;
  variants?: Array<{
    sku?: string | null;
    price: number;
    stock: number;
    deletedAt?: Date | null;
    isActive: boolean;
    options?: Array<{ option?: { value: string } | null }>;
  }>;
}): ProductSearchDoc;

export function applyProductIndexSettings(
  index: unknown,
  options?: { wait?: boolean; waitOptions?: unknown },
): Promise<unknown[]>;
