export type BrandCatalogItem = {
  id: string | number;
  name: string;
  slug: string;
  logo?: string | null;
  imageClass?: string;
};

export function brandProductHref(brand: Pick<BrandCatalogItem, "slug">) {
  const params = new URLSearchParams();
  params.set("brand", brand.slug);
  return `/products?${params.toString()}`;
}

export function mapDbBrandsToCatalogItems(
  dbBrands: Array<{ id: string; name: string; slug: string; logoUrl?: string | null }>,
): BrandCatalogItem[] {
  return dbBrands.map((brand) => ({
    id: brand.id,
    name: brand.name,
    slug: brand.slug,
    logo: brand.logoUrl ?? null,
  }));
}
