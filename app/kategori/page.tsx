import type { Metadata } from "next";
import { prisma } from "@/lib/prisma";
import { CategoryTabPage, type CategorySummary } from "@/components/CategoryTabPage";

export const revalidate = 300;

export const metadata: Metadata = {
  title: "Kategori",
  description: "Pilih kategori produk Natalo Petshop dengan cepat.",
};

export default async function KategoriPage() {
  const categories = await prisma.category
    .findMany({
      where: { products: { some: { isActive: true } } },
      orderBy: { name: "asc" },
      select: {
        id: true,
        name: true,
        slug: true,
        products: {
          where: { isActive: true },
          orderBy: { createdAt: "desc" },
          take: 1,
          select: { imageUrl: true },
        },
        _count: { select: { products: { where: { isActive: true } } } },
      },
    })
    .catch(() => []);

  const initialCategories: CategorySummary[] = categories.map((category) => ({
    id: category.id,
    name: category.name,
    slug: category.slug,
    productCount: category._count.products,
    imageUrl: category.products[0]?.imageUrl ?? null,
  }));

  return <CategoryTabPage initialCategories={initialCategories} />;
}
