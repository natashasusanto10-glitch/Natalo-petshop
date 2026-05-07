import { prisma } from "@/lib/prisma";
import { sampleProducts } from "@/lib/sample-data";

export type StoreProduct = {
  id: string;
  name: string;
  slug: string;
  description: string;
  price: number;
  memberPrice: number | null;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
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
    const product = await prisma.product.findUnique({ where: { slug } });
    return product ?? sampleProducts.find((item) => item.slug === slug) ?? null;
  } catch {
    return sampleProducts.find((item) => item.slug === slug) ?? null;
  }
}
