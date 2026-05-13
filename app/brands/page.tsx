import type { Metadata } from "next";
import { BrandDirectoryClient } from "@/components/brands/BrandDirectoryClient";
import { mergeBrandsWithFallback } from "@/lib/brand-catalog";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Semua Brand",
  description: "Pilih brand favoritmu di Natalo Petshop.",
};

export default async function BrandsPage() {
  const dbBrands = await prisma.brand
    .findMany({
      where: { products: { some: { isActive: true } } },
      orderBy: { name: "asc" },
      select: {
        id: true,
        name: true,
        slug: true,
        logoUrl: true,
      },
    })
    .catch(() => []);

  const brands = mergeBrandsWithFallback(dbBrands);

  return <BrandDirectoryClient brands={brands} />;
}
