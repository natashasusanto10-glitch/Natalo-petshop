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

export async function getProducts(): Promise<StoreProduct[]> {
  try {
    const products = await prisma.product.findMany({
      where: { isActive: true },
      orderBy: { createdAt: "desc" },
    });
    return products.length ? products : sampleProducts;
  } catch {
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
