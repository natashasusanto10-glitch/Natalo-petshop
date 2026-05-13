import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import Image from "next/image";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { FlashSaleCountdown } from "@/components/home/FlashSaleCountdown";
import { BrandChoiceSection } from "@/components/home/BrandChoiceSection";
import HeroBanner from "@/components/home/HeroBanner";
import TrustMarquee from "@/components/home/TrustMarquee";
import type { TrustItem } from "@/data/trustItems";
import { ExternalLink } from "@/components/ExternalLink";
import { FALLBACK_BRANDS, mergeBrandsWithFallback } from "@/lib/brand-catalog";

const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const revalidate = 60;

export const metadata: Metadata = {
  title: `${brand} | Toko Hewan Peliharaan & Aquarium`,
  description:
    "Toko hewan peliharaan terpercaya di Medan. Pakan ikan, aksesoris kucing, anjing, burung, dan kebutuhan aquarium — lengkap, original, dikirim cepat.",
  openGraph: {
    title: `${brand} | Toko Hewan Peliharaan & Aquarium`,
    description: "Pakan, aksesoris, dan kebutuhan hewan peliharaan kamu — lengkap, berkualitas, dikirim cepat.",
    url: siteUrl,
    images: [{ url: `${siteUrl}/icon.svg`, width: 512, height: 512, alt: brand }],
  },
};

type HomeIconName =
  | "box"
  | "bird"
  | "cat"
  | "clinic"
  | "dog"
  | "fish"
  | "flame"
  | "gift"
  | "grooming"
  | "house-call-grooming"
  | "medal"
  | "paw"
  | "rabbit"
  | "reptile"
  | "sparkles"
  | "tag"
  | "truck"
  | "voucher-pet"
  | "dog-training"
  | "chat";

const SHORTCUT_ITEMS: {
  icon: HomeIconName;
  label: string;
  href: string;
  bg: string;
  color: string;
  external?: boolean;
}[] = [
  { icon: "sparkles", label: "Produk Baru", href: "/products?sort=newest", bg: "bg-blue-50", color: "text-blue-600" },
  { icon: "medal", label: "Terlaris", href: "/products?sort=popular", bg: "bg-amber-50", color: "text-amber-600" },
  { icon: "voucher-pet", label: "Voucher", href: "/member", bg: "bg-pink-50", color: "text-pink-600" },
  { icon: "flame", label: "Trending", href: "/products?promo=1", bg: "bg-red-50", color: "text-red-600" },
  {
    icon: "house-call-grooming",
    label: "House Call Grooming",
    href: "https://wa.me/6281330003880?text=Halo%20Natalo%2C%20saya%20ingin%20booking%20House%20Call%20Grooming",
    bg: "bg-emerald-50",
    color: "text-emerald-600",
    external: true,
  },
  {
    icon: "dog-training",
    label: "Dog Training",
    href: "https://wa.me/6281330003880?text=Halo%20Natalo%2C%20saya%20ingin%20konsultasi%20Dog%20Training",
    bg: "bg-violet-50",
    color: "text-violet-600",
    external: true,
  },
];

function getJakartaMidnight() {
  const now = new Date();
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jakarta",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = fmt.formatToParts(now);
  const y = parts.find((p) => p.type === "year")!.value;
  const m = parts.find((p) => p.type === "month")!.value;
  const d = parts.find((p) => p.type === "day")!.value;
  return new Date(`${y}-${m}-${d}T23:59:59+07:00`).getTime();
}

function HomeIcon({
  name,
  className = "h-7 w-7",
}: {
  name: HomeIconName;
  className?: string;
}) {
  if (name === "voucher-pet") {
    return (
      <svg
        aria-hidden="true"
        className={className}
        viewBox="0 0 48 48"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M14 10 L11 6 L11 14 Z" fill="currentColor" stroke="none" />
        <path d="M30 10 L33 6 L33 14 Z" fill="currentColor" stroke="none" />
        <ellipse cx="22" cy="16" rx="11" ry="9" fill="#FFF" stroke="currentColor" />
        <circle cx="18" cy="15.5" r="1.2" fill="currentColor" stroke="none" />
        <circle cx="26" cy="15.5" r="1.2" fill="currentColor" stroke="none" />
        <path d="M22 20 Q20.5 22 19 21" />
        <path d="M22 20 Q23.5 22 25 21" />
        <path d="M9 28 H35 a2 2 0 0 1 2 2 V36 a2 2 0 0 1-2 2 H9 a2 2 0 0 1 0-4 a2 2 0 0 1 0-4 Z" fill="#FFF" stroke="currentColor" />
        <path d="M22 28 V38" strokeDasharray="1.5 2" />
        <text x="14.5" y="35" fontSize="5" fontWeight="800" fill="currentColor" stroke="none">50%</text>
        <ellipse cx="11" cy="26.5" rx="3.2" ry="2.4" fill="currentColor" stroke="none" />
        <ellipse cx="33" cy="26.5" rx="3.2" ry="2.4" fill="currentColor" stroke="none" />
      </svg>
    );
  }

  if (name === "house-call-grooming") {
    return (
      <svg
        aria-hidden="true"
        className={className}
        viewBox="0 0 48 48"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M8 22 L24 9 L40 22 V39 a2 2 0 0 1-2 2 H10 a2 2 0 0 1-2-2 Z" fill="#FFF" />
        <path d="M6 23 L24 8 L42 23" />
        <circle cx="18" cy="32" r="3" />
        <circle cx="30" cy="32" r="3" />
        <path d="M20.5 30 L29 22 M27.5 30 L19 22" />
        <ellipse cx="24" cy="17" rx="2.2" ry="1.7" fill="currentColor" stroke="none" />
        <ellipse cx="21" cy="14.5" rx="1" ry="1.3" fill="currentColor" stroke="none" />
        <ellipse cx="23" cy="13" rx="1" ry="1.3" fill="currentColor" stroke="none" />
        <ellipse cx="25" cy="13" rx="1" ry="1.3" fill="currentColor" stroke="none" />
        <ellipse cx="27" cy="14.5" rx="1" ry="1.3" fill="currentColor" stroke="none" />
      </svg>
    );
  }

  if (name === "dog-training") {
    return (
      <svg
        aria-hidden="true"
        className={className}
        viewBox="0 0 48 48"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M11 14 Q8 22 12 28 L16 26 Z" fill="currentColor" stroke="none" />
        <path d="M37 14 Q40 22 36 28 L32 26 Z" fill="currentColor" stroke="none" />
        <ellipse cx="24" cy="22" rx="11" ry="10" fill="#FFF" />
        <ellipse cx="24" cy="27" rx="5" ry="4" fill="#FFF" />
        <ellipse cx="24" cy="25" rx="1.6" ry="1.2" fill="currentColor" stroke="none" />
        <circle cx="20" cy="21" r="1.1" fill="currentColor" stroke="none" />
        <circle cx="28" cy="21" r="1.1" fill="currentColor" stroke="none" />
        <path d="M24 27 V29 M24 29 Q22.5 30.5 21 30 M24 29 Q25.5 30.5 27 30" />
        <rect x="34" y="36" width="9" height="6" rx="1.5" fill="currentColor" stroke="none" />
        <circle cx="43" cy="39" r="1.4" fill="#F5F3FF" stroke="none" />
        <path d="M30 35 Q28 37 30 39 M27 33 Q24 37 27 41" />
        <path d="M16 30 Q24 34 32 30" />
        <circle cx="24" cy="32.5" r="1.2" fill="currentColor" stroke="none" />
      </svg>
    );
  }

  const paths: Record<Exclude<HomeIconName, "voucher-pet" | "house-call-grooming" | "dog-training">, ReactNode> = {
    box: (
      <>
        <path d="m4 8 8 4 8-4" />
        <path d="M12 12v8" />
        <path d="M5 8.5v7l7 4 7-4v-7l-7-4-7 4Z" />
      </>
    ),
    bird: (
      <>
        <path d="M5 14c3.5-5.5 8-7 14-5" />
        <path d="M7 13c.5 4 3.5 6 7 5" />
        <path d="M11 10c2 1 3.5 2.5 4 5" />
        <path d="M18 9l2-2" />
        <path d="M15 7.5V5" />
      </>
    ),
    cat: (
      <>
        <path d="M6 10V5l4 3h4l4-3v5" />
        <path d="M6 10c0 5 3 8 6 8s6-3 6-8" />
        <path d="M9 13h.01" />
        <path d="M15 13h.01" />
        <path d="M11 16h2" />
      </>
    ),
    clinic: (
      <>
        <path d="M5 20V8l7-4 7 4v12" />
        <path d="M9 20v-6h6v6" />
        <path d="M12 8v4" />
        <path d="M10 10h4" />
      </>
    ),
    dog: (
      <>
        <path d="M6 10c0-3 2.5-5 6-5s6 2 6 5v3c0 3-2.5 5-6 5s-6-2-6-5v-3Z" />
        <path d="M6 11 3.5 9.5" />
        <path d="m18 11 2.5-1.5" />
        <path d="M9 12h.01" />
        <path d="M15 12h.01" />
        <path d="M11 15h2" />
      </>
    ),
    fish: (
      <>
        <path d="M3 12s4-6 10-6c4 0 7 6 7 6s-3 6-7 6c-6 0-10-6-10-6Z" />
        <path d="m20 12 2.5-3v6L20 12Z" />
        <path d="M8 12h.01" />
        <path d="M14 8c-1 2-1 6 0 8" />
      </>
    ),
    flame: (
      <>
        <path d="M12 21c3.5-1 6-3.5 6-7 0-3-1.8-5-4.2-7.3-.7 2.3-2.1 3.4-3.8 4.7.2-2-.3-3.8-1.5-5.4C6.4 8.5 5 11.4 5 14c0 3.5 2.5 6 7 7Z" />
      </>
    ),
    gift: (
      <>
        <path d="M4 11h16v9H4z" />
        <path d="M3 7h18v4H3z" />
        <path d="M12 7v13" />
        <path d="M12 7c-1.2-2.4-4.5-3-5-1-.5 2 2.5 2 5 1Z" />
        <path d="M12 7c1.2-2.4 4.5-3 5-1 .5 2-2.5 2-5 1Z" />
      </>
    ),
    grooming: (
      <>
        <path d="m5 19 14-14" />
        <path d="M7.5 7.5 5 5" />
        <path d="M16.5 16.5 19 19" />
        <circle cx="7" cy="17" r="2" />
        <circle cx="17" cy="7" r="2" />
      </>
    ),
    medal: (
      <>
        <path d="m8 13-2.5 8L8.5 19l1.5 3 2-5.5" />
        <path d="m16 13 2.5 8L15.5 19l-1.5 3-2-5.5" />
        <circle cx="12" cy="11" r="5.5" />
        <path d="M12 8l1 2 2.2.3-1.6 1.5.4 2.2L12 13l-2 1 .4-2.2L8.8 10.3 11 10Z" fill="currentColor" stroke="none" />
      </>
    ),
    paw: (
      <>
        <path d="M8 20c-2 0-3-1.2-3-2.7 0-2.4 3.1-4.8 7-4.8s7 2.4 7 4.8c0 1.5-1 2.7-3 2.7-1.4 0-2.5-.8-4-.8s-2.6.8-4 .8Z" />
        <circle cx="6.5" cy="10" r="1.8" />
        <circle cx="10" cy="7" r="1.8" />
        <circle cx="14" cy="7" r="1.8" />
        <circle cx="17.5" cy="10" r="1.8" />
      </>
    ),
    rabbit: (
      <>
        <path d="M8 11C6.5 6 7 3 9 3c1.5 0 2.5 3.5 3 7" />
        <path d="M16 11c1.5-5 1-8-1-8-1.5 0-2.5 3.5-3 7" />
        <path d="M6 14c0 4 2.5 6 6 6s6-2 6-6c0-2.5-2-4-6-4s-6 1.5-6 4Z" />
        <path d="M10 15h.01" />
        <path d="M14 15h.01" />
      </>
    ),
    reptile: (
      <>
        <path d="M4 14c3-4 7-5 12-3l4 1" />
        <path d="M7 16c2 2 5 2.5 8 1" />
        <path d="M16 11l2-3" />
        <path d="m15 17 2 3" />
        <path d="M6 14l-2-2" />
      </>
    ),
    sparkles: (
      <>
        <path d="M12 3l1.7 5.1L19 10l-5.3 1.9L12 17l-1.7-5.1L5 10l5.3-1.9L12 3Z" />
        <path d="m5 15 .7 2.1L8 18l-2.3.9L5 21l-.7-2.1L2 18l2.3-.9L5 15Z" />
      </>
    ),
    tag: (
      <>
        <path d="M4 12V5h7l9 9-7 7-9-9Z" />
        <path d="M8 8h.01" />
      </>
    ),
    truck: (
      <>
        <path d="M3 7h11v9H3z" />
        <path d="M14 10h4l3 3v3h-7" />
        <circle cx="7" cy="18" r="2" />
        <circle cx="17" cy="18" r="2" />
      </>
    ),
    chat: (
      <>
        <path d="M5 18.5V7c0-1.5 1.2-2.5 2.8-2.5h8.4C17.8 4.5 19 5.5 19 7v5c0 1.5-1.2 2.5-2.8 2.5H10l-5 4Z" />
        <path d="M9 9h6" />
        <path d="M9 12h4" />
      </>
    ),
  };

  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.8"
      viewBox="0 0 24 24"
    >
      {paths[name]}
    </svg>
  );
}

function categoryIconFor(name: string): HomeIconName {
  const normalized = name.toLowerCase();

  if (normalized.includes("ikan") || normalized.includes("aquarium")) return "fish";
  if (normalized.includes("kucing")) return "cat";
  if (normalized.includes("anjing")) return "dog";
  if (normalized.includes("burung")) return "bird";
  if (normalized.includes("kelinci")) return "rabbit";
  if (normalized.includes("reptil")) return "reptile";

  return "paw";
}

export default async function HomePage() {
  const wa =
    process.env.NEXT_PUBLIC_WA_NUMBER ||
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ||
    "";
  const waUrl = `https://wa.me/${wa.replace("+", "")}?text=${encodeURIComponent("Halo Natalo Petshop, saya mau tanya...")}`;
  const trustItems: TrustItem[] = [
    {
      icon: "truck",
      iconClass: "text-natalo-700",
      text: "Gratis Ongkir Area Medan",
    },
    {
      icon: "shield",
      iconClass: "text-emerald-600",
      text: "Produk Original 100%",
    },
    {
      icon: "chat",
      iconClass: "text-natalo-700",
      text: "Konsultasi via WhatsApp",
      href: waUrl,
      external: true,
      showLinkIcon: true,
    },
    {
      icon: "paw",
      iconClass: "text-natalo-700",
      text: "Petshop Medan Terpercaya",
      href: "/tentang-kami",
    },
    {
      icon: "gift",
      iconClass: "text-amber-500",
      text: "Banyak Promo Setiap Hari",
    },
  ];

  const [products, popularCategories, dbFeaturedBrands] = await Promise.all([
    getProducts({ take: 24 }),
    prisma.category
      .findMany({
        where: { products: { some: { isActive: true } } },
        take: 6,
        orderBy: { products: { _count: "desc" } },
        select: {
          name: true,
          slug: true,
          products: {
            where: { isActive: true },
            take: 1,
            select: { imageUrl: true },
          },
          _count: { select: { products: { where: { isActive: true } } } },
        },
      })
      .catch(() => []),
    prisma.brand
      .findMany({
        where: { products: { some: { isActive: true } } },
        take: 12,
        orderBy: { products: { _count: "desc" } },
        select: {
          id: true,
          name: true,
          slug: true,
          logoUrl: true,
        },
      })
      .catch(() => []),
  ]);

  const fallbackPopularCategories = [
    { name: "Makanan Kucing", slug: "makanan-kucing", products: [], _count: { products: 0 } },
    { name: "Makanan Anjing", slug: "makanan-anjing", products: [], _count: { products: 0 } },
    { name: "Aquarium & Ikan", slug: "aquarium-kolam", products: [], _count: { products: 0 } },
    { name: "Kandang & Carrier", slug: "kandang-carrier", products: [], _count: { products: 0 } },
    { name: "Grooming Tools", slug: "grooming-tools", products: [], _count: { products: 0 } },
    { name: "Snack & Treat", slug: "snack-treat-kucing", products: [], _count: { products: 0 } },
  ];
  const homeCategories = popularCategories.length > 0 ? popularCategories : fallbackPopularCategories;

  const flashSaleProducts = products
    .filter((p) => p.discountPrice !== null && p.discountPrice < p.price)
    .slice(0, 6);
  const bestSellers = [...products]
    .sort((a, b) => b.reviewCount - a.reviewCount || b.avgRating - a.avgRating)
    .slice(0, 6);

  const allBrands = mergeBrandsWithFallback(dbFeaturedBrands);
  const featuredSlugs = new Set(FALLBACK_BRANDS.slice(0, 18).map((brand) => brand.slug));
  const featuredBrands = [
    ...FALLBACK_BRANDS.slice(0, 18).map((brand) => allBrands.find((item) => item.slug === brand.slug) ?? brand),
    ...allBrands.filter((brand) => !featuredSlugs.has(brand.slug)),
  ].slice(0, 18);

  const flashSaleEnd = getJakartaMidnight();

  // JSON-LD structured data — Organization + LocalBusiness + WebSite untuk
  // Google Knowledge Panel + Sitelinks search box. Single @graph supaya
  // multiple schema bisa di-emit dalam 1 script tag.
  const phoneRaw = process.env.NEXT_PUBLIC_WA_NUMBER ?? process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? "+6281289997113";
  const phone = phoneRaw.startsWith("+") ? phoneRaw : `+${phoneRaw.replace(/^0/, "62")}`;
  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": `${siteUrl}#organization`,
        name: brand,
        url: siteUrl,
        logo: `${siteUrl}/icons/icon-512x512.png`,
        sameAs: [
          "https://www.instagram.com/natalopetshop/",
          "https://www.tiktok.com/@natalopetshop",
        ],
        contactPoint: {
          "@type": "ContactPoint",
          telephone: phone,
          contactType: "customer service",
          areaServed: "ID",
          availableLanguage: ["Indonesian"],
        },
      },
      {
        "@type": "Store",
        "@id": `${siteUrl}#store`,
        name: brand,
        image: `${siteUrl}/icons/icon-512x512.png`,
        url: siteUrl,
        telephone: phone,
        priceRange: "Rp",
        address: {
          "@type": "PostalAddress",
          streetAddress: "Jl. MT. Haryono No. 103 BCD",
          addressLocality: "Medan",
          addressRegion: "Sumatera Utara",
          addressCountry: "ID",
        },
        openingHoursSpecification: [
          {
            "@type": "OpeningHoursSpecification",
            dayOfWeek: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
            opens: "09:00",
            closes: "18:00",
          },
        ],
      },
      {
        "@type": "WebSite",
        "@id": `${siteUrl}#website`,
        url: siteUrl,
        name: brand,
        inLanguage: "id-ID",
        publisher: { "@id": `${siteUrl}#organization` },
        potentialAction: {
          "@type": "SearchAction",
          target: {
            "@type": "EntryPoint",
            urlTemplate: `${siteUrl}/search?q={search_term_string}`,
          },
          "query-input": "required name=search_term_string",
        },
      },
    ],
  };

  return (
    <div className="min-h-screen overflow-x-hidden bg-[#FAFAFA] pb-[calc(7rem+env(safe-area-inset-bottom))] md:pb-10">
      <script
        type="application/ld+json"
        // eslint-disable-next-line react/no-danger
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <TrustMarquee items={trustItems} />

      {/* ── 2. BANNER CAROUSEL UTAMA ── */}
      <section className="pt-3">
        <HeroBanner />
      </section>

      {/* ── 4. HASHTAG CAMPAIGN + SHORTCUT GRID ── */}
      <section className="mt-4 px-4">
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
          {SHORTCUT_ITEMS.map((s) => {
            const content = (
              <>
                <div
                  className={`flex h-14 w-14 items-center justify-center rounded-full ${s.bg} ${s.color} shadow-sm`}
                >
                  <HomeIcon name={s.icon} className="h-7 w-7" />
                </div>
                <span className="text-center text-[11px] font-medium leading-tight text-zinc-700">
                  {s.label}
                </span>
              </>
            );

            if (s.external) {
              return (
                <ExternalLink
                  key={s.label}
                  href={s.href}
                  className="flex flex-col items-center gap-1.5 rounded-xl p-2 transition active:opacity-90"
                >
                  {content}
                </ExternalLink>
              );
            }

            return (
              <Link
                key={s.label}
                href={s.href}
                className="flex flex-col items-center gap-1.5 rounded-xl p-2 transition active:opacity-90"
              >
                {content}
              </Link>
            );
          })}
        </div>
      </section>

      {/* ── 5. FLASH SALE ── */}
      {flashSaleProducts.length > 0 && (
        <section className="mt-5">
          <div className="flex items-center justify-between gap-2 px-4">
            <div>
              <h2 className="text-lg font-black text-zinc-900">⚡ Flash Sale</h2>
              <p className="mt-0.5 text-xs text-zinc-500">Diskon spesial sampai tengah malam</p>
            </div>
            <FlashSaleCountdown endsAt={flashSaleEnd} />
          </div>
          <div className="mt-3 flex snap-x snap-mandatory gap-2.5 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {flashSaleProducts.map((p) => {
              const finalPrice = p.discountPrice ?? p.price;
              const off = Math.max(1, Math.round(((p.price - finalPrice) / p.price) * 100));
              return (
                <Link
                  key={p.id}
                  href={`/products/${p.slug}`}
                  className="w-[42vw] min-w-[124px] max-w-[150px] shrink-0 snap-start overflow-hidden rounded-2xl border border-[#eef3fb] bg-white shadow-sm active:opacity-90"
                >
                  <div className="relative aspect-square w-full bg-white p-2">
                    {p.imageUrl ? (
                      <Image
                        src={p.imageUrl}
                        alt={p.name}
                        fill
                        loading="lazy"
                        sizes="(max-width: 640px) 42vw, 150px"
                        placeholder="blur"
                        blurDataURL={IMAGE_BLUR_GRAY}
                        className="object-contain p-2"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-zinc-300">
                        <HomeIcon name="box" className="h-10 w-10" />
                      </div>
                    )}
                    <span className="absolute left-1.5 top-1.5 rounded bg-red-500 px-1.5 py-0.5 text-[10px] font-black text-white">
                      -{off}%
                    </span>
                  </div>
                  <div className="p-2">
                    <p className="line-clamp-2 text-[11px] font-bold text-zinc-700">{p.name}</p>
                    <div className="mt-1 flex items-center justify-between gap-1">
                      <p className="min-w-0 truncate text-[13px] font-black leading-tight text-[#1E5FBF]">
                        {formatRupiah(finalPrice)}
                      </p>
                      {p.avgRating > 0 && (
                        <span className="shrink-0 text-[10px] font-bold text-amber-500">★ {p.avgRating.toFixed(1)}</span>
                      )}
                    </div>
                    <p className="text-[10px] text-zinc-400 line-through">
                      {formatRupiah(p.price)}
                    </p>
                  </div>
                </Link>
              );
            })}
          </div>
        </section>
      )}

      {/* ── 11. PRODUK TERLARIS ── */}
      <section className="mt-5">
        <div className="flex items-end justify-between px-4">
          <h2 className="text-base font-black text-zinc-900 sm:text-lg">🏆 Produk Terlaris</h2>
          <Link href="/products?sort=popular" className="text-xs font-bold text-blue-600">
            Lihat semua
          </Link>
        </div>
        <div className="mt-3 flex snap-x snap-mandatory gap-2.5 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {bestSellers.map((p, i) => {
            const finalPrice = p.memberPrice ?? p.discountPrice ?? p.price;
            const hasMarkdown =
              (p.memberPrice != null && p.memberPrice < p.price) ||
              (p.discountPrice != null && p.discountPrice < p.price);
            return (
              <Link
                key={p.id}
                href={`/products/${p.slug}`}
                className="relative w-[42vw] min-w-[124px] max-w-[150px] shrink-0 snap-start overflow-hidden rounded-2xl border border-[#eef3fb] bg-white shadow-sm active:opacity-90"
              >
                {i < 3 && (
                  <span
                    className={`absolute left-1.5 top-1.5 z-10 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-black shadow ${
                      i === 0
                        ? "bg-amber-400 text-white"
                        : i === 1
                          ? "bg-zinc-300 text-zinc-700"
                          : "bg-blue-300 text-white"
                    }`}
                    aria-label={`Peringkat ${i + 1}`}
                  >
                    {i + 1}
                  </span>
                )}
                <div className="relative aspect-square w-full bg-white p-2">
                  {p.imageUrl ? (
                    <Image
                      src={p.imageUrl}
                      alt={p.name}
                      fill
                      loading="lazy"
                      sizes="(max-width: 640px) 42vw, 150px"
                      placeholder="blur"
                      blurDataURL={IMAGE_BLUR_GRAY}
                      className="object-contain p-2"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-zinc-300">
                      <HomeIcon name="box" className="h-10 w-10" />
                    </div>
                  )}
                </div>
                <div className="p-2">
                  <p className="line-clamp-2 min-h-[2.1rem] text-[11px] font-bold leading-snug text-zinc-700">
                    {p.name}
                  </p>
                  <div className="mt-1 flex items-center justify-between gap-1">
                    <p className="min-w-0 truncate text-[13px] font-black leading-tight text-[#1E5FBF]">
                      {formatRupiah(finalPrice)}
                    </p>
                    {p.avgRating > 0 && (
                      <span className="shrink-0 text-[10px] font-bold text-amber-500">★ {p.avgRating.toFixed(1)}</span>
                    )}
                  </div>
                  {hasMarkdown && (
                    <p className="text-[10px] text-zinc-400 line-through">
                      {formatRupiah(p.price)}
                    </p>
                  )}
                </div>
              </Link>
            );
          })}
        </div>
      </section>

      <BrandChoiceSection brands={featuredBrands} />

      {homeCategories.length > 0 && (
        <section className="mt-5">
          <h2 className="px-4 text-base font-black text-zinc-900 sm:text-lg">Kategori Populer</h2>
          <div className="mt-2 flex snap-x snap-mandatory gap-2.5 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {homeCategories.map((cat) => (
              <Link
                key={cat.slug}
                href={`/products?kategori=${cat.slug}`}
                className="w-[31vw] min-w-[106px] max-w-[130px] shrink-0 snap-start overflow-hidden rounded-2xl border border-[#eef3fb] bg-white shadow-sm active:opacity-90"
              >
                <div className="relative aspect-[4/3] w-full bg-white p-2">
                  {cat.products[0]?.imageUrl ? (
                    <Image
                      src={cat.products[0].imageUrl}
                      alt={cat.name}
                      fill
                      loading="lazy"
                      sizes="(max-width: 640px) 31vw, 130px"
                      placeholder="blur"
                      blurDataURL={IMAGE_BLUR_GRAY}
                      className="object-contain p-2"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-blue-300">
                      <HomeIcon name={categoryIconFor(cat.name)} className="h-8 w-8" />
                    </div>
                  )}
                </div>
                <div className="px-2 py-2">
                  <p className="line-clamp-2 min-h-[2rem] text-[11px] font-bold leading-tight text-zinc-900">{cat.name}</p>
                  <p className="mt-1 text-[10px] text-zinc-500">
                    {cat._count.products > 0 ? `${cat._count.products} produk` : "Lihat produk"}
                  </p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}

    </div>
  );
}
