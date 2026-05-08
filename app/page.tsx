import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import Image from "next/image";
import { ProductCard } from "@/components/ProductCard";
import { getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { FlashSaleCountdown } from "@/components/home/FlashSaleCountdown";
import { HomeSearchBar } from "@/components/home/HomeSearchBar";
import HeroBanner from "@/components/home/HeroBanner";
import TrustMarquee from "@/components/home/TrustMarquee";

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
  | "paw"
  | "rabbit"
  | "reptile"
  | "sparkles"
  | "tag"
  | "truck"
  | "chat";

const SHORTCUT_ITEMS: {
  icon: HomeIconName;
  label: string;
  href: string;
  bg: string;
  color: string;
}[] = [
  { icon: "sparkles", label: "Produk Baru", href: "/products?sort=newest", bg: "bg-orange-50", color: "text-orange-600" },
  { icon: "flame", label: "Sedang Laris", href: "/products?sort=popular", bg: "bg-red-50", color: "text-red-600" },
  { icon: "gift", label: "Voucher", href: "/member", bg: "bg-pink-50", color: "text-pink-600" },
  { icon: "tag", label: "Promo Hemat", href: "/products?promo=1", bg: "bg-yellow-50", color: "text-amber-600" },
  { icon: "clinic", label: "Klinik", href: "/tentang-kami", bg: "bg-emerald-50", color: "text-emerald-600" },
  { icon: "grooming", label: "Grooming", href: "/tentang-kami", bg: "bg-blue-50", color: "text-blue-600" },
  { icon: "truck", label: "Cek Ongkir", href: "/checkout", bg: "bg-indigo-50", color: "text-indigo-600" },
  { icon: "chat", label: "Konsultasi", href: "/tentang-kami", bg: "bg-purple-50", color: "text-purple-600" },
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
  const paths: Record<HomeIconName, ReactNode> = {
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

  const [products, popularCategories] = await Promise.all([
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
  ]);

  const flashSaleProducts = products
    .filter((p) => p.discountPrice !== null && p.discountPrice < p.price)
    .slice(0, 6);
  const bestSellers = [...products]
    .sort((a, b) => b.reviewCount - a.reviewCount || b.avgRating - a.avgRating)
    .slice(0, 6);

  const flashSaleEnd = getJakartaMidnight();

  return (
    <div className="bg-[#FAFAFA] pb-8">
      {/* ── 1. SEARCH BAR + CS ICON (mobile sticky) ── */}
      <HomeSearchBar waUrl={waUrl} />

      <TrustMarquee />

      {/* ── 2. BANNER CAROUSEL UTAMA ── */}
      <section className="pt-3">
        <HeroBanner />
      </section>

      {/* ── 4. HASHTAG CAMPAIGN + SHORTCUT GRID ── */}
      <section className="mt-6 px-4">
        <p className="text-center text-sm font-black text-orange-600">#PetshopMedanTerpercaya</p>
        <div className="mt-4 grid grid-cols-4 gap-2">
          {SHORTCUT_ITEMS.map((s) => (
            <Link
              key={s.label}
              href={s.href}
              className="flex flex-col items-center gap-1.5 rounded-xl p-2 transition active:opacity-90"
            >
              <div
                className={`flex h-14 w-14 items-center justify-center rounded-full ${s.bg} ${s.color} shadow-sm`}
              >
                <HomeIcon name={s.icon} className="h-7 w-7" />
              </div>
              <span className="text-[11px] font-medium leading-tight text-zinc-700 text-center">
                {s.label}
              </span>
            </Link>
          ))}
        </div>
      </section>

      {/* ── 5. FLASH SALE ── */}
      {flashSaleProducts.length > 0 && (
        <section className="mt-6">
          <div className="flex items-center justify-between gap-2 px-4">
            <div>
              <h2 className="text-lg font-black text-zinc-900">⚡ Flash Sale</h2>
              <p className="mt-0.5 text-xs text-zinc-500">Diskon spesial sampai tengah malam</p>
            </div>
            <FlashSaleCountdown endsAt={flashSaleEnd} />
          </div>
          <div className="mt-3 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {flashSaleProducts.map((p) => {
              const finalPrice = p.discountPrice ?? p.price;
              const off = Math.max(1, Math.round(((p.price - finalPrice) / p.price) * 100));
              return (
                <Link
                  key={p.id}
                  href={`/products/${p.slug}`}
                  className="w-[140px] shrink-0 snap-start overflow-hidden rounded-xl border border-[#f5f5f5] bg-white shadow-sm active:opacity-90"
                >
                  <div className="relative aspect-square w-full bg-zinc-50">
                    {p.imageUrl ? (
                      <Image
                        src={p.imageUrl}
                        alt={p.name}
                        fill
                        loading="lazy"
                        sizes="140px"
                        className="object-cover"
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
                    <p className="mt-1 text-sm font-black text-[#E8711F]">
                      {formatRupiah(finalPrice)}
                    </p>
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

      {/* ── 6. KATEGORI POPULER ── */}
      {popularCategories.length > 0 && (
        <section className="mt-6">
          <h2 className="px-4 text-lg font-black text-zinc-900">📈 Kategori Populer</h2>
          <div className="mt-3 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {popularCategories.map((cat) => (
              <Link
                key={cat.slug}
                href={`/products?kategori=${cat.slug}`}
                className="w-[140px] shrink-0 snap-start overflow-hidden rounded-2xl border border-[#f5f5f5] bg-white shadow-sm active:opacity-90"
              >
                <div className="relative aspect-square w-full bg-zinc-50">
                  {cat.products[0]?.imageUrl ? (
                    <Image
                      src={cat.products[0].imageUrl}
                      alt={cat.name}
                      fill
                      loading="lazy"
                      sizes="140px"
                      className="object-cover"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-orange-300">
                      <HomeIcon name={categoryIconFor(cat.name)} className="h-12 w-12" />
                    </div>
                  )}
                </div>
                <div className="p-3">
                  <p className="text-sm font-black text-zinc-900">{cat.name}</p>
                  <p className="mt-0.5 text-[11px] text-zinc-500">
                    {cat._count.products} produk
                  </p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* ── 11. PRODUK TERLARIS ── */}
      <section className="mt-6 px-4">
        <div className="flex items-end justify-between">
          <h2 className="text-lg font-black text-zinc-900">🏆 Produk Terlaris</h2>
          <Link href="/products?sort=popular" className="text-xs font-bold text-orange-600">
            Lihat semua
          </Link>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3">
          {bestSellers.map((p, i) => (
            <div key={p.id} className="relative">
              {i < 3 && (
                <span
                  className={`absolute left-1.5 top-1.5 z-10 flex h-7 w-7 items-center justify-center rounded-full text-sm shadow ${
                    i === 0
                      ? "bg-amber-400 text-white"
                      : i === 1
                        ? "bg-zinc-300 text-zinc-700"
                        : "bg-orange-300 text-white"
                  }`}
                  aria-label={`Peringkat ${i + 1}`}
                >
                  {i === 0 ? "🥇" : i === 1 ? "🥈" : "🥉"}
                </span>
              )}
              <ProductCard product={p} variant="compact" />
            </div>
          ))}
        </div>
      </section>

    </div>
  );
}
