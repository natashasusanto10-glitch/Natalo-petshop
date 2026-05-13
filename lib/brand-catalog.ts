export type BrandCatalogItem = {
  id: string | number;
  name: string;
  slug: string;
  logo?: string | null;
  imageClass?: string;
};

export const FALLBACK_BRANDS: BrandCatalogItem[] = [
  { id: "royal-canin", name: "Royal Canin", slug: "royal-canin", logo: "/brands/royal-canin.png", imageClass: "max-h-[42px] max-w-[100px]" },
  { id: "whiskas", name: "Whiskas", slug: "whiskas", logo: "/brands/whiskas.png", imageClass: "max-h-[46px] max-w-[98px]" },
  { id: "me-o", name: "Me-O", slug: "me-o", logo: "/brands/me-o.png", imageClass: "max-h-[42px] max-w-[88px]" },
  { id: "happy-dog", name: "Happy Dog", slug: "happy-dog", logo: "/brands/happy-dog.png", imageClass: "max-h-[42px] max-w-[104px]" },
  { id: "reflex", name: "Reflex", slug: "reflex", logo: "/brands/reflex.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "pro-plan", name: "Pro Plan", slug: "pro-plan", logo: "/brands/pro-plan.png", imageClass: "max-h-[44px] max-w-[104px]" },
  { id: "pedigree", name: "Pedigree", slug: "pedigree", logo: "/brands/pedigree.png", imageClass: "max-h-[48px] max-w-[100px]" },
  { id: "ciao", name: "Ciao", slug: "ciao", logo: "/brands/Ciao.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "fancy-feast", name: "Fancy Feast", slug: "fancy-feast", logo: "/brands/Fancy Feasy.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "monge", name: "Monge", slug: "monge" },
  { id: "nutri-plan", name: "Nutri Plan", slug: "nutri-plan" },
  { id: "hills", name: "Hill's", slug: "hills", logo: "/brands/Science Diet.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "taste-of-the-wild", name: "Taste of the Wild", slug: "taste-of-the-wild" },
  { id: "cats-best", name: "Cat's Best", slug: "cats-best" },
  { id: "bozita", name: "Bozita", slug: "bozita" },
  { id: "equilibrio", name: "Equilibrio", slug: "equilibrio" },
  { id: "ferplast", name: "Ferplast", slug: "ferplast" },
  { id: "tetra", name: "Tetra", slug: "tetra" },
  { id: "amara", name: "Amara", slug: "amara", logo: "/brands/amara.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "amori", name: "Amori", slug: "amori", logo: "/brands/amori.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "angels", name: "Angels", slug: "angels", logo: "/brands/angels.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "sakkai", name: "Sakkai", slug: "sakkai", logo: "/brands/sakkai.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "happy-cat", name: "Happy Cat", slug: "happy-cat", logo: "/brands/happy-cat.png", imageClass: "max-h-[40px] max-w-[102px]" },
  { id: "nature-bridge", name: "Nature Bridge", slug: "nature-bridge", logo: "/brands/nature-bridge.png", imageClass: "max-h-[42px] max-w-[104px]" },
  { id: "kitchen-flavour", name: "Kitchen Flavor", slug: "kitchen-flavour", logo: "/brands/kitchen-flavor.png", imageClass: "max-h-[48px] max-w-[96px]" },
  { id: "bravery", name: "Bravery", slug: "bravery", logo: "/brands/Bravery.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "friskies", name: "Friskies", slug: "friskies", logo: "/brands/Friskies.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "kalbe-animal-health", name: "Kalbe Animal Health", slug: "kalbe-animal-health", logo: "/brands/Kalbe Animal Health.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "majes", name: "Majes", slug: "majes", logo: "/brands/Majes.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "nexgard", name: "NexGard", slug: "nexgard", logo: "/brands/Nexgard.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "nexgard-spectra", name: "NexGard Spectra", slug: "nexgard-spectra", logo: "/brands/nexgard spectra.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "purina-one", name: "Purina One", slug: "purina-one", logo: "/brands/Purina One.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "animalco", name: "Animal&Co", slug: "animalco", logo: "/brands/animal&co.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "coucou", name: "Coucou", slug: "coucou", logo: "/brands/coucou.png", imageClass: "max-h-[46px] max-w-[104px]" },
  { id: "drontal", name: "Drontal", slug: "drontal", logo: "/brands/drontal.png", imageClass: "max-h-[46px] max-w-[104px]" },
];

export const LOCAL_BRAND_LOGOS = new Map(
  FALLBACK_BRANDS.filter((brand) => brand.logo).map((brand) => [brand.slug, brand.logo ?? null]),
);

export function brandProductHref(brand: Pick<BrandCatalogItem, "name" | "slug">) {
  const params = new URLSearchParams();
  params.set("brand", brand.slug);
  return `/products?${params.toString()}`;
}

export function mergeBrandsWithFallback(
  dbBrands: Array<{ id: string; name: string; slug: string; logoUrl?: string | null }>,
) {
  const bySlug = new Map<string, BrandCatalogItem>();

  for (const brand of FALLBACK_BRANDS) {
    bySlug.set(brand.slug, brand);
  }

  for (const brand of dbBrands) {
    const fallback = bySlug.get(brand.slug);
    bySlug.set(brand.slug, {
      ...fallback,
      id: brand.id,
      name: brand.name,
      slug: brand.slug,
      logo: brand.logoUrl ?? fallback?.logo ?? LOCAL_BRAND_LOGOS.get(brand.slug) ?? null,
      imageClass: fallback?.imageClass,
    });
  }

  return Array.from(bySlug.values()).sort((a, b) => a.name.localeCompare(b.name, "id"));
}
