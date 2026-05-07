import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import { ProductCard } from "@/components/ProductCard";
import { getProducts } from "@/lib/products";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { BannerCarousel, type HomeBanner } from "@/components/home/BannerCarousel";
import { TestimonialSlider, type HomeTestimonial } from "@/components/home/TestimonialSlider";
import { FlashSaleCountdown } from "@/components/home/FlashSaleCountdown";
import { HomeSearchBar } from "@/components/home/HomeSearchBar";

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

const HOME_BANNERS: HomeBanner[] = [
  {
    id: "b1",
    title: "Diskon Besar Pakan Premium",
    subtitle: "Promo Spesial",
    emoji: "🐱",
    bgFrom: "#f97316",
    bgTo: "#fb923c",
    href: "/products",
  },
  {
    id: "b2",
    title: "Member Baru Hemat Rp50.000",
    subtitle: "Member Benefit",
    emoji: "🎁",
    bgFrom: "#10b981",
    bgTo: "#34d399",
    href: "/member/register",
  },
  {
    id: "b3",
    title: "Aquarium Set Lengkap Mulai 199K",
    subtitle: "Aquarium",
    emoji: "🐠",
    bgFrom: "#3b82f6",
    bgTo: "#60a5fa",
    href: "/products?kategori=ikan",
  },
  {
    id: "b4",
    title: "Konsultasi Hewan Gratis 24 Jam",
    subtitle: "Konsultasi",
    emoji: "💬",
    bgFrom: "#8b5cf6",
    bgTo: "#a78bfa",
    href: "/tentang-kami",
  },
];

const SHORTCUT_ITEMS = [
  { emoji: "🆕", label: "Produk Baru", href: "/products?sort=newest", bg: "bg-orange-50" },
  { emoji: "🔥", label: "Sedang Laris", href: "/products?sort=popular", bg: "bg-red-50" },
  { emoji: "🎁", label: "Voucher", href: "/member", bg: "bg-pink-50" },
  { emoji: "💰", label: "Promo Hemat", href: "/products?promo=1", bg: "bg-yellow-50" },
  { emoji: "🏥", label: "Klinik", href: "/tentang-kami", bg: "bg-emerald-50" },
  { emoji: "✂️", label: "Grooming", href: "/tentang-kami", bg: "bg-blue-50" },
  { emoji: "🚚", label: "Cek Ongkir", href: "/checkout", bg: "bg-indigo-50" },
  { emoji: "🐾", label: "Konsultasi", href: "/tentang-kami", bg: "bg-purple-50" },
];

const PET_CATEGORIES = [
  { label: "Ikan", emoji: "🐟", color: "bg-orange-50" },
  { label: "Kucing", emoji: "🐱", color: "bg-orange-50" },
  { label: "Anjing", emoji: "🐶", color: "bg-yellow-50" },
  { label: "Burung", emoji: "🦜", color: "bg-green-50" },
  { label: "Kelinci", emoji: "🐰", color: "bg-pink-50" },
  { label: "Reptil", emoji: "🦎", color: "bg-emerald-50" },
];

const TESTIMONIALS: HomeTestimonial[] = [
  {
    id: "t1",
    name: "Sarah W.",
    pet: "Kucing Persia, Mochi",
    petEmoji: "🐱",
    avatarEmoji: "👩",
    quote:
      "Pengiriman super cepat, pakannya original. Sudah langganan 6 bulan dan Mochi makin sehat.",
    rating: 5,
  },
  {
    id: "t2",
    name: "Budi P.",
    pet: "Anjing Golden, Rocky",
    petEmoji: "🐶",
    avatarEmoji: "👨",
    quote: "Harga bersaing, admin responsif via WA. Konsultasi soal vitamin Rocky dibantu detail.",
    rating: 5,
  },
  {
    id: "t3",
    name: "Linda T.",
    pet: "Ikan Cupang, 12 ekor",
    petEmoji: "🐠",
    avatarEmoji: "👩‍🦰",
    quote: "Aquarium lengkap, packing aman. Cupangku selamat semua sampai rumah, mantap!",
    rating: 4,
  },
  {
    id: "t4",
    name: "Andi K.",
    pet: "Burung Murai",
    petEmoji: "🦜",
    avatarEmoji: "🧑",
    quote: "Bayar via QRIS gampang banget. Voucher member bikin belanja lebih hemat.",
    rating: 5,
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

export default async function HomePage() {
  const wa =
    process.env.NEXT_PUBLIC_WA_NUMBER ||
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ||
    "";
  const waUrl = `https://wa.me/${wa.replace("+", "")}?text=${encodeURIComponent("Halo Natalo Petshop, saya mau tanya...")}`;

  const [products, popularCategories, mostSearchedCategories] = await Promise.all([
    getProducts({ take: 24 }),
    prisma.category
      .findMany({
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
    prisma.category
      .findMany({
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
  const newArrivals = products.slice(0, 6);
  const bestSellers = [...products]
    .sort((a, b) => b.reviewCount - a.reviewCount || b.avgRating - a.avgRating)
    .slice(0, 6);

  const flashSaleEnd = getJakartaMidnight();

  return (
    <div className="bg-[#FAFAFA] pb-8">
      {/* ── 1. SEARCH BAR + CS ICON (mobile sticky) ── */}
      <HomeSearchBar waUrl={waUrl} />

      {/* ── 2. BANNER CAROUSEL UTAMA ── */}
      <section className="pt-3">
        <BannerCarousel banners={HOME_BANNERS} />
      </section>

      {/* ── 3. 2 BANNER KECIL SIDE BY SIDE ── */}
      <section className="mt-6 px-4">
        <div className="grid grid-cols-2 gap-3">
          <Link
            href="/tentang-kami"
            className="relative flex h-[160px] flex-col justify-between overflow-hidden rounded-xl p-4 text-white shadow-sm active:opacity-90"
            style={{ background: "linear-gradient(135deg, #ec4899, #f472b6)" }}
          >
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider opacity-90">Promo</p>
              <p className="mt-1 text-base font-black leading-tight">Grooming Hemat 30%</p>
            </div>
            <span className="text-3xl">✂️</span>
          </Link>
          <Link
            href="/tentang-kami"
            className="relative flex h-[160px] flex-col justify-between overflow-hidden rounded-xl p-4 text-white shadow-sm active:opacity-90"
            style={{ background: "linear-gradient(135deg, #14b8a6, #2dd4bf)" }}
          >
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider opacity-90">Paket</p>
              <p className="mt-1 text-base font-black leading-tight">Vaksin Hemat Mulai 75K</p>
            </div>
            <span className="text-3xl">🏥</span>
          </Link>
        </div>
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
                className={`flex h-14 w-14 items-center justify-center rounded-full ${s.bg} text-2xl shadow-sm`}
              >
                {s.emoji}
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
                      <div className="flex h-full items-center justify-center text-3xl">🐾</div>
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
                    <div className="flex h-full items-center justify-center text-4xl">🐾</div>
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

      {/* ── 7. PRODUK BARU MASUK ── */}
      <section className="mt-6 px-4">
        <div className="flex items-end justify-between">
          <h2 className="text-lg font-black text-zinc-900">🆕 Produk Baru Masuk</h2>
          <Link href="/products?sort=newest" className="text-xs font-bold text-orange-600">
            Lihat semua
          </Link>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3">
          {newArrivals.map((p, i) => (
            <ProductCard key={p.id} product={p} variant="compact" priority={i < 2} />
          ))}
        </div>
      </section>

      {/* ── 8. TESTIMONI PELANGGAN ── */}
      <section className="mt-6 px-4">
        <h2 className="text-lg font-black text-zinc-900">💛 Cerita Pelanggan</h2>
        <p className="mt-0.5 text-xs text-zinc-500">Apa kata mereka tentang Natalo</p>
        <div className="mt-3">
          <TestimonialSlider testimonials={TESTIMONIALS} />
        </div>
      </section>

      {/* ── 9. PROMO BUNDLE (3 BANNER STACK) ── */}
      <section className="mt-6 px-4">
        <div className="space-y-3">
          <Link
            href="/checkout"
            className="flex items-center justify-between gap-3 rounded-xl p-5 text-white shadow-sm active:opacity-90"
            style={{ background: "linear-gradient(135deg, #16a34a, #4ade80)" }}
          >
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider opacity-90">Gratis</p>
              <p className="mt-1 text-base font-black">Gratis Ongkir Min. 100K</p>
              <p className="mt-0.5 text-xs opacity-90">Khusus area Medan</p>
            </div>
            <span className="text-4xl">🚚</span>
          </Link>
          <Link
            href="/products"
            className="flex items-center justify-between gap-3 rounded-xl p-5 text-white shadow-sm active:opacity-90"
            style={{ background: "linear-gradient(135deg, #f97316, #fb923c)" }}
          >
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider opacity-90">Bundle</p>
              <p className="mt-1 text-base font-black">Beli 2 Hemat 15%</p>
              <p className="mt-0.5 text-xs opacity-90">Kombinasi pakan + aksesoris</p>
            </div>
            <span className="text-4xl">📦</span>
          </Link>
          <Link
            href="/member/register"
            className="flex items-center justify-between gap-3 rounded-xl p-5 text-white shadow-sm active:opacity-90"
            style={{ background: "linear-gradient(135deg, #7c3aed, #a78bfa)" }}
          >
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wider opacity-90">Member</p>
              <p className="mt-1 text-base font-black">Harga Member Lebih Hemat</p>
              <p className="mt-0.5 text-xs opacity-90">Daftar gratis 2 menit</p>
            </div>
            <span className="text-4xl">🎁</span>
          </Link>
        </div>
      </section>

      {/* ── 10. KATEGORI HEWAN ── */}
      <section className="mt-6 px-4">
        <h2 className="text-lg font-black text-zinc-900">🐾 Belanja by Hewan</h2>
        <div className="mt-3 grid grid-cols-3 gap-3">
          {PET_CATEGORIES.map((pet) => (
            <Link
              key={pet.label}
              href={`/products?kategori=${pet.label.toLowerCase()}`}
              className="flex flex-col items-center gap-2 rounded-2xl border border-[#f5f5f5] bg-white p-4 shadow-sm active:opacity-90"
            >
              <div
                className={`flex h-14 w-14 items-center justify-center rounded-full ${pet.color} text-3xl`}
              >
                {pet.emoji}
              </div>
              <span className="text-xs font-bold text-zinc-700">{pet.label}</span>
            </Link>
          ))}
        </div>
      </section>

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

      {/* ── 12. LAGI BANYAK DICARI ── */}
      {mostSearchedCategories.length > 0 && (
        <section className="mt-6 px-4">
          <h2 className="text-lg font-black text-zinc-900">🔍 Lagi Banyak Dicari</h2>
          <div className="mt-3 grid grid-cols-2 gap-3">
            {mostSearchedCategories.map((cat) => (
              <Link
                key={cat.slug}
                href={`/products?kategori=${cat.slug}`}
                className="flex items-center gap-3 overflow-hidden rounded-xl border border-[#f5f5f5] bg-white p-2 shadow-sm active:opacity-90"
              >
                <div className="relative h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-zinc-50">
                  {cat.products[0]?.imageUrl ? (
                    <Image
                      src={cat.products[0].imageUrl}
                      alt={cat.name}
                      fill
                      loading="lazy"
                      sizes="56px"
                      className="object-cover"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-2xl">🐾</div>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-bold text-zinc-900">{cat.name}</p>
                  <p className="mt-0.5 text-[11px] text-zinc-500">
                    {cat._count.products} Produk
                  </p>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* ── 13. CTA KONSULTASI WA ── */}
      <section className="mt-6 px-4">
        <a
          href={waUrl}
          target="_blank"
          rel="noreferrer"
          className="flex items-center justify-between gap-3 rounded-2xl p-5 text-white shadow-sm active:opacity-90"
          style={{ background: "linear-gradient(135deg, #16a34a, #22c55e)" }}
        >
          <div>
            <p className="text-base font-black leading-tight">Bingung pilih produk?</p>
            <p className="mt-1 text-xs opacity-90">Konsultasi gratis dengan tim Natalo via WhatsApp.</p>
            <span className="mt-3 inline-block rounded-full bg-white/20 px-4 py-1.5 text-xs font-bold backdrop-blur-sm">
              💬 Chat Sekarang
            </span>
          </div>
          <span className="text-5xl drop-shadow-lg">🐾</span>
        </a>
      </section>
    </div>
  );
}
