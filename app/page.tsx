import type { Metadata } from "next";
import Link from "next/link";
import { ProductCard } from "@/components/ProductCard";
import { WhatsAppButton } from "@/components/WhatsAppButton";
import { getProducts } from "@/lib/products";

const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const metadata: Metadata = {
  title: `${brand} | Toko Hewan Peliharaan & Aquarium`,
  description: "Toko hewan peliharaan terpercaya di Indonesia. Pakan ikan, aksesoris kucing, anjing, burung, dan kebutuhan aquarium — lengkap, original, dikirim cepat.",
  openGraph: {
    title: `${brand} | Toko Hewan Peliharaan & Aquarium`,
    description: "Pakan, aksesoris, dan kebutuhan hewan peliharaan kamu — lengkap, berkualitas, dikirim cepat.",
    url: siteUrl,
    images: [{ url: `${siteUrl}/icon.svg`, width: 512, height: 512, alt: brand }],
  },
};

const PET_CATEGORIES = [
  { label: "Ikan", emoji: "🐟", color: "bg-blue-50" },
  { label: "Kucing", emoji: "🐱", color: "bg-orange-50" },
  { label: "Anjing", emoji: "🐶", color: "bg-yellow-50" },
  { label: "Burung", emoji: "🦜", color: "bg-green-50" },
  { label: "Kelinci", emoji: "🐰", color: "bg-pink-50" },
  { label: "Reptil", emoji: "🦎", color: "bg-emerald-50" },
];

const INFO_ITEMS = [
  {
    icon: "✅",
    title: "Produk Original & Berkualitas",
    desc: "Semua produk kami original langsung dari distributor resmi. Kualitas terjamin.",
  },
  {
    icon: "🚀",
    title: "Pengiriman Cepat",
    desc: "Order diproses same day. Tersedia berbagai kurir untuk seluruh Indonesia.",
  },
  {
    icon: "💬",
    title: "Konsultasi Gratis via WhatsApp",
    desc: "Bingung pilih produk? Tim kami siap bantu rekomendasikan yang terbaik.",
  },
  {
    icon: "🏆",
    title: "Dipercaya Ribuan Pelanggan",
    desc: "Sudah melayani ribuan pelanggan setia dengan rating kepuasan tinggi.",
  },
];

const PARTNER_BRANDS = ["Hikari", "Sera", "Jebo", "Atman", "API", "Tetra", "Boyu", "Eheim"];

const BLOG_POSTS = [
  {
    emoji: "🐠",
    tag: "Aquarium",
    title: "Tips Merawat Ikan Hias agar Tetap Sehat dan Warna Tetap Cerah",
    date: "1 Mei 2026",
    slug: "#",
  },
  {
    emoji: "🐱",
    tag: "Kucing",
    title: "Panduan Memilih Pakan Kucing Sesuai Usia dan Kondisi Kesehatan",
    date: "28 Apr 2026",
    slug: "#",
  },
  {
    emoji: "🐶",
    tag: "Anjing",
    title: "5 Aksesoris Wajib untuk Anjing Peliharaan yang Aktif",
    date: "22 Apr 2026",
    slug: "#",
  },
];

export default async function HomePage() {
  const wa = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || "";
  const products = await getProducts();
  const featured = products.slice(0, 3);
  const bestSelling = products.slice(0, 6);

  return (
    <div>
      {/* ── 1. HERO ── */}
      <section className="overflow-hidden bg-white">
        <div className="mx-auto grid max-w-6xl items-center gap-8 px-4 py-16 md:grid-cols-2 md:py-24">
          <div>
            <span className="inline-block rounded-full bg-orange-100 px-4 py-1.5 text-sm font-semibold text-orange-500">
              {brand}
            </span>
            <h1 className="mt-5 text-4xl font-black leading-tight tracking-tight text-gray-900 md:text-5xl">
              Toko hewan peliharaan yang{" "}
              <span className="text-orange-500">terpercaya</span>
            </h1>
            <p className="mt-5 max-w-md text-gray-500">
              Pakan, aksesoris, dan kebutuhan hewan peliharaan kamu — lengkap, berkualitas, dikirim cepat ke seluruh Indonesia.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link
                href="/products"
                className="rounded-full bg-orange-500 px-7 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
              >
                Belanja Sekarang
              </Link>
              <WhatsAppButton />
            </div>
          </div>

          <div className="relative flex items-center justify-center">
            <div className="relative flex h-80 w-80 items-center justify-center rounded-full bg-orange-500 md:h-96 md:w-96">
              <div className="absolute inset-8 rounded-full bg-orange-400/30" />
              <span className="absolute right-8 top-10 text-3xl opacity-25">🐾</span>
              <span className="absolute bottom-12 left-10 text-xl opacity-20">🐾</span>
              <span className="relative z-10 text-8xl drop-shadow-lg">🐠</span>
            </div>
            <div className="absolute -bottom-4 -left-4 h-20 w-20 rounded-full bg-orange-300 opacity-50" />
            <div className="absolute -right-6 top-10 h-12 w-12 rounded-full bg-orange-400 opacity-40" />
          </div>
        </div>
      </section>

      {/* ── 2. CATEGORIES ── */}
      <section className="bg-gray-50 py-14">
        <div className="mx-auto max-w-6xl px-4">
          <h2 className="text-2xl font-black text-gray-900">Kategori hewan</h2>
          <div className="mt-8 grid grid-cols-3 gap-4 sm:grid-cols-6">
            {PET_CATEGORIES.map((pet) => (
              <Link
                key={pet.label}
                href={`/products?kategori=${pet.label.toLowerCase()}`}
                className="group flex flex-col items-center gap-3"
              >
                <div className={`flex h-20 w-20 items-center justify-center rounded-full ${pet.color} shadow-sm transition group-hover:shadow-md group-hover:ring-2 group-hover:ring-orange-400`}>
                  <span className="text-4xl">{pet.emoji}</span>
                </div>
                <span className="text-sm font-semibold text-gray-700">{pet.label}</span>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* ── 3. FEATURED PRODUCTS ── */}
      <section className="py-14">
        <div className="mx-auto max-w-6xl px-4">
          <div className="flex items-end justify-between gap-4">
            <div>
              <h2 className="text-2xl font-black text-gray-900">Produk unggulan</h2>
              <p className="mt-1 text-sm text-gray-500">Pilihan produk premium dari toko kami</p>
            </div>
            <Link href="/products" className="text-sm font-semibold text-orange-500 hover:underline">
              Lihat semua →
            </Link>
          </div>
          <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {featured.map((p) => <ProductCard key={p.id} product={p} />)}
          </div>
        </div>
      </section>

      {/* ── 4. INFO BLOCK ── */}
      <section className="bg-orange-500 py-14">
        <div className="mx-auto max-w-6xl px-4">
          <div className="mb-10 text-center text-white">
            <h2 className="text-2xl font-black">Kenapa belanja di {brand}?</h2>
            <p className="mt-2 text-sm text-orange-100">
              Kami hadir untuk memastikan hewan peliharaan kamu mendapatkan yang terbaik.
            </p>
          </div>
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            {INFO_ITEMS.map((item) => (
              <div key={item.title} className="rounded-2xl bg-white/10 p-6 text-white backdrop-blur-sm">
                <span className="text-3xl">{item.icon}</span>
                <h3 className="mt-3 font-bold leading-snug">{item.title}</h3>
                <p className="mt-2 text-sm text-orange-100">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── 5. LOGOS ── */}
      <section className="border-y border-gray-100 bg-white py-10">
        <div className="mx-auto max-w-6xl px-4">
          <p className="mb-8 text-center text-sm font-semibold uppercase tracking-widest text-gray-400">
            Brand yang kami jual
          </p>
          <div className="flex flex-wrap items-center justify-center gap-x-10 gap-y-5">
            {PARTNER_BRANDS.map((brand) => (
              <span
                key={brand}
                className="text-lg font-black tracking-tight text-gray-300 transition hover:text-orange-400"
              >
                {brand}
              </span>
            ))}
          </div>
        </div>
      </section>

      {/* ── 6. BEST SELLING PRODUCTS ── */}
      <section className="bg-gray-50 py-14">
        <div className="mx-auto max-w-6xl px-4">
          <div className="flex items-end justify-between gap-4">
            <div>
              <h2 className="text-2xl font-black text-gray-900">Produk terlaris</h2>
              <p className="mt-1 text-sm text-gray-500">Favorit pelanggan setia kami</p>
            </div>
            <Link href="/products" className="text-sm font-semibold text-orange-500 hover:underline">
              Lihat semua →
            </Link>
          </div>
          <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {bestSelling.map((p) => <ProductCard key={p.id} product={p} />)}
          </div>
        </div>
      </section>

      {/* ── 7. SHOP BY PET ── */}
      <section className="py-14">
        <div className="mx-auto max-w-6xl px-4">
          <div className="flex items-center justify-between">
            <h2 className="text-2xl font-black text-gray-900">Belanja by hewan</h2>
            <Link href="/products" className="text-sm font-semibold text-orange-500 hover:underline">
              Lihat semua →
            </Link>
          </div>
          <div className="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
            {PET_CATEGORIES.map((pet) => (
              <Link
                key={pet.label}
                href={`/products?kategori=${pet.label.toLowerCase()}`}
                className="group flex flex-col items-center gap-3 rounded-2xl border border-gray-100 bg-white p-5 shadow-sm transition hover:border-orange-300 hover:shadow-md"
              >
                <span className="text-5xl">{pet.emoji}</span>
                <span className="text-sm font-semibold text-gray-700">{pet.label}</span>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* ── 8. NEWS & BLOG ── */}
      <section className="bg-gray-50 py-14">
        <div className="mx-auto max-w-6xl px-4">
          <div className="flex items-end justify-between gap-4">
            <div>
              <h2 className="text-2xl font-black text-gray-900">Tips & Artikel</h2>
              <p className="mt-1 text-sm text-gray-500">Info perawatan hewan peliharaan untuk kamu</p>
            </div>
          </div>
          <div className="mt-8 grid gap-6 sm:grid-cols-3">
            {BLOG_POSTS.map((post) => (
              <Link
                key={post.title}
                href={post.slug}
                className="group overflow-hidden rounded-2xl bg-white shadow-sm transition hover:shadow-md"
              >
                <div className="flex h-44 items-center justify-center bg-orange-50 text-7xl">
                  {post.emoji}
                </div>
                <div className="p-5">
                  <span className="rounded-full bg-orange-100 px-3 py-1 text-xs font-semibold text-orange-500">
                    {post.tag}
                  </span>
                  <h3 className="mt-3 font-bold leading-snug text-gray-900 group-hover:text-orange-500">
                    {post.title}
                  </h3>
                  <p className="mt-2 text-xs text-gray-400">{post.date}</p>
                </div>
              </Link>
            ))}
          </div>

          <div className="mt-10 rounded-2xl bg-white p-8 text-center shadow-sm">
            <p className="text-sm text-gray-500">Butuh saran produk yang tepat untuk hewan kamu?</p>
            <a
              href={`https://wa.me/${wa.replace("+", "")}?text=${encodeURIComponent("Halo, saya mau konsultasi produk untuk hewan peliharaan saya.")}`}
              target="_blank"
              rel="noreferrer"
              className="mt-4 inline-flex items-center gap-2 rounded-full bg-orange-500 px-7 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
            >
              💬 Konsultasi via WhatsApp
            </a>
          </div>
        </div>
      </section>
    </div>
  );
}
