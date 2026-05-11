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
  memberPrice?: number | null;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  gallery: string[];
  hasVariants: boolean;
  avgRating: number;
  reviewCount: number;
  categorySlug?: string | null;
  // hanya diisi oleh getProductBySlug
  variantAttrs?: StoreVariantAttribute[];
  variants?: StoreProductVariant[];
};

function normalizeProductWeight(name: string, slug: string, weightGram: number) {
  const text = `${name} ${slug}`.toLowerCase();
  if (text.includes("maxi-cat") && text.includes("20kg")) return 20000;
  return weightGram;
}

const variantInclude = {
  variantAttrs: {
    orderBy: { position: "asc" as const },
    include: { options: { orderBy: { position: "asc" as const } } },
  },
  variants: {
    where: { deletedAt: null },
    include: { options: { select: { optionId: true } } },
    orderBy: { createdAt: "asc" as const },
  },
};

/**
 * Filter "Produk Baru" → window createdAt sejak titik waktu tertentu.
 * Helper untuk konvert ke Date threshold.
 */
function newProductCutoff(filter: NewProductFilter | undefined): Date | null {
  if (!filter || filter === "newest") return null;
  const now = new Date();
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  if (filter === "today") return start;
  if (filter === "this-week") {
    start.setDate(start.getDate() - 7);
    return start;
  }
  if (filter === "this-month") {
    start.setDate(1);
    return start;
  }
  return null;
}

export type NewProductFilter = "today" | "this-week" | "this-month" | "newest";
export type PopularFilter =
  | "best-seller"
  | "most-searched"
  | "highest-rating"
  | "most-bought";

function buildOrderBy(
  newFilter?: NewProductFilter,
  popularFilter?: PopularFilter,
): { createdAt: "desc" } | { reviewCount: "desc" } | { avgRating: "desc" } | Array<{ avgRating: "desc" } | { reviewCount: "desc" }> {
  // Popular filter has priority over new filter for ordering
  if (popularFilter === "highest-rating") {
    return [{ avgRating: "desc" }, { reviewCount: "desc" }];
  }
  if (
    popularFilter === "best-seller" ||
    popularFilter === "most-bought" ||
    popularFilter === "most-searched"
  ) {
    // Pakai reviewCount sebagai proxy popularitas — produk dgn review
    // banyak biasanya = sering dibeli.
    return { reviewCount: "desc" };
  }
  // Default & new filter sort
  return { createdAt: "desc" };
}

export async function getProducts(opts?: {
  category?: string;
  search?: string;
  take?: number;
  skip?: number;
  newFilter?: NewProductFilter;
  popularFilter?: PopularFilter;
}): Promise<StoreProduct[]> {
  const { category, search, take, skip, newFilter, popularFilter } = opts ?? {};
  const createdAtCutoff = newProductCutoff(newFilter);
  try {
    const products = await prisma.product.findMany({
      where: {
        isActive: true,
        ...(category ? { category: { slug: category } } : {}),
        ...(search ? { name: { contains: search, mode: "insensitive" } } : {}),
        ...(createdAtCutoff ? { createdAt: { gte: createdAtCutoff } } : {}),
      },
      orderBy: buildOrderBy(newFilter, popularFilter),
      take,
      skip,
      include: {
        category: { select: { slug: true } },
        variants: {
          where: { deletedAt: null, isActive: true },
          select: { price: true, stock: true },
        },
      },
    });

    if (!products.length) {
      if (category || search) return [];
      return sampleProducts;
    }

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
          memberPrice: p.memberPrice,
          stock: totalStock,
          weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
          imageUrl: p.imageUrl,
          gallery: p.gallery ?? [],
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
        memberPrice: p.memberPrice,
        stock: p.stock,
        weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
        imageUrl: p.imageUrl,
        gallery: p.gallery ?? [],
        hasVariants: false,
        avgRating: p.avgRating,
        reviewCount: p.reviewCount,
        categorySlug: p.category?.slug ?? null,
      };
    });
  } catch {
    if (category || search) return [];
    return sampleProducts;
  }
}

export async function getProductsCount(opts?: {
  category?: string;
  search?: string;
  newFilter?: NewProductFilter;
}): Promise<number> {
  const { category, search, newFilter } = opts ?? {};
  const createdAtCutoff = newProductCutoff(newFilter);
  try {
    return await prisma.product.count({
      where: {
        isActive: true,
        ...(category ? { category: { slug: category } } : {}),
        ...(search ? { name: { contains: search, mode: "insensitive" } } : {}),
        ...(createdAtCutoff ? { createdAt: { gte: createdAtCutoff } } : {}),
      },
    });
  } catch {
    return 0;
  }
}

export async function getProductBySlug(slug: string): Promise<StoreProduct | null> {
  try {
    // Cari by slug dulu — kalau tidak ada, fallback by id. Berguna untuk
    // legacy cart items yang belum punya slug (tersimpan productId only),
    // atau deep-link by id.
    let p = await prisma.product.findUnique({
      where: { slug },
      include: { ...variantInclude, category: { select: { slug: true } } },
    });
    if (!p) {
      p = await prisma.product.findUnique({
        where: { id: slug },
        include: { ...variantInclude, category: { select: { slug: true } } },
      });
    }
    if (!p) return sampleProducts.find((item) => item.slug === slug) ?? null;

    if (p.hasVariants && p.variants.length > 0) {
      const activeVariants = p.variants.filter((v) => v.isActive);
      const prices = activeVariants.map((v) => v.price);
      const totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);
      return {
        id: p.id,
        name: p.name,
        slug: p.slug,
        description: p.description,
        price: prices.length ? Math.min(...prices) : p.price,
        discountPrice: null,
        memberPrice: p.memberPrice,
        stock: totalStock,
        weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
        imageUrl: p.imageUrl,
        gallery: p.gallery ?? [],
        hasVariants: true,
        avgRating: p.avgRating,
        reviewCount: p.reviewCount,
        categorySlug: p.category?.slug ?? null,
        variantAttrs: p.variantAttrs as unknown as StoreVariantAttribute[],
        variants: p.variants as unknown as StoreProductVariant[],
      };
    }

    return {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: p.price,
      discountPrice: p.discountPrice,
      memberPrice: p.memberPrice,
      stock: p.stock,
      weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
      imageUrl: p.imageUrl,
      gallery: p.gallery ?? [],
      hasVariants: false,
      avgRating: p.avgRating,
      reviewCount: p.reviewCount,
      categorySlug: p.category?.slug ?? null,
    };
  } catch {
    return sampleProducts.find((item) => item.slug === slug) ?? null;
  }
}
