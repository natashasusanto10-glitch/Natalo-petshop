import { prisma } from "@/lib/prisma";
import { sampleProducts } from "@/lib/sample-data";

export type StoreVariantOption = {
  id: string;
  value: string;
  position: number;
};

export type StoreVariantAttribute = {
  id: string;
  name: string;
  position: number;
  options: StoreVariantOption[];
};

export type StoreProductVariant = {
  id: string;
  sku: string | null;
  price: number;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  isActive: boolean;
  deletedAt: Date | null;
  options: { optionId: string }[];
};

export type StoreProduct = {
  id: string;
  name: string;
  slug: string;
  description: string;
  price: number;
  discountPrice: number | null;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  hasVariants: boolean;
  avgRating: number;
  reviewCount: number;
  categorySlug?: string | null;
  // hanya diisi oleh getProductBySlug
  variantAttrs?: StoreVariantAttribute[];
  variants?: StoreProductVariant[];
};

export async function getProducts(opts?: { category?: string; search?: string }): Promise<StoreProduct[]> {
  const { category, search } = opts ?? {};
  try {
    const products = await prisma.product.findMany({
      where: {
        isActive: true,
        ...(category ? { category: { slug: category } } : {}),
        ...(search ? { name: { contains: search, mode: "insensitive" } } : {}),
      },
      orderBy: { createdAt: "desc" },
      include: {
        category: { select: { slug: true } },
        variants: {
          where: { deletedAt: null, isActive: true },
          select: { price: true, stock: true },
        },
      },
    });

    if (!products.length) return sampleProducts;

    return products.map((p) => {
      if (p.hasVariants && p.variants.length > 0) {
        const prices = p.variants.map((v) => v.price);
        const totalStock = p.variants.reduce((s, v) => s + v.stock, 0);
        return {
          id: p.id,
          name: p.name,
          slug: p.slug,
          description: p.description,
          price: Math.min(...prices),
          discountPrice: null,
          stock: totalStock,
          weightGram: p.weightGram,
          imageUrl: p.imageUrl,
          hasVariants: true,
          avgRating: p.avgRating,
          reviewCount: p.reviewCount,
          categorySlug: p.category?.slug ?? null,
        };
      }
      return {
        id: p.id,
        name: p.name,
        slug: p.slug,
        description: p.description,
        price: p.price,
        discountPrice: p.discountPrice,
        stock: p.stock,
        weightGram: p.weightGram,
        imageUrl: p.imageUrl,
        hasVariants: false,
        avgRating: p.avgRating,
        reviewCount: p.reviewCount,
        categorySlug: p.category?.slug ?? null,
      };
    });
    if (products.length) return products;
    if (category || search) return [];
    return sampleProducts;
  } catch {
    if (category || search) return [];
    return sampleProducts;
  }
}

export async function getProductBySlug(slug: string): Promise<StoreProduct | null> {
  try {
    const p = await prisma.product.findUnique({
      where: { slug },
      include: { ...variantInclude, category: { select: { slug: true } } },
    });
    if (!p) return sampleProducts.find((item) => item.slug === slug) ?? null;

    if (p.hasVariants && p.variants.length > 0) {
      const prices = p.variants.filter((v) => v.isActive).map((v) => v.price);
      const totalStock = p.variants.filter((v) => v.isActive).reduce((s, v) => s + v.stock, 0);
      return {
        id: p.id,
        name: p.name,
        slug: p.slug,
        description: p.description,
        price: prices.length ? Math.min(...prices) : p.price,
        discountPrice: null,
        stock: totalStock,
        weightGram: p.weightGram,
        imageUrl: p.imageUrl,
        hasVariants: true,
        avgRating: p.avgRating,
        reviewCount: p.reviewCount,
        categorySlug: p.category?.slug ?? null,
        variantAttrs: p.variantAttrs,
        variants: p.variants as StoreProductVariant[],
      };
    }

    return {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: p.price,
      discountPrice: p.discountPrice,
      stock: p.stock,
      weightGram: p.weightGram,
      imageUrl: p.imageUrl,
      hasVariants: false,
      avgRating: p.avgRating,
      reviewCount: p.reviewCount,
      categorySlug: p.category?.slug ?? null,
    };
  } catch {
    return sampleProducts.find((item) => item.slug === slug) ?? null;
  }
}
