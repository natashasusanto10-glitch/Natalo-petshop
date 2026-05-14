import type { Metadata } from "next";
import { BrandDirectoryClient } from "@/components/brands/BrandDirectoryClient";
import { mapDbBrandsToCatalogItems } from "@/lib/brand-catalog";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Semua Brand",
  description: "Pilih brand favoritmu di Natalo Petshop.",
};

export default async function BrandsPage() {
  const dbBrands = await prisma.brand
    .findMany({
      where: {
        isActive: true,
        name: { not: "" },
      },
      orderBy: [{ position: "asc" }, { createdAt: "desc" }, { name: "asc" }],
      select: {
        id: true,
        name: true,
        slug: true,
        logoUrl: true,
      },
    })
    .catch(() => []);

  const brands = mapDbBrandsToCatalogItems(dbBrands);

  return <BrandDirectoryClient brands={brands} />;
}
