/**
 * Loader hero slides untuk halaman depan WEB (server-only).
 *
 * Sumber utama: tabel `HomeBanner` (dikelola admin via /admin/banners) —
 * SAMA dengan sumber yang dipakai app Flutter lewat /api/banners. Sebelum
 * ini `app/page.tsx` memanggil `<HeroBanner />` tanpa props sehingga web
 * selalu memakai daftar statis `data/heroSlides.ts` dan mengabaikan banner
 * admin sepenuhnya: banner yang diatur di panel admin tampil di app tapi
 * tidak pernah di web.
 *
 * Fallback ke `data/heroSlides.ts` HANYA kalau DB kosong (admin belum
 * setup) atau query gagal, supaya hero tidak pernah kosong.
 *
 * Kenapa file ini terpisah dari `lib/home-banners.ts`: file itu berisi
 * helper murni (tanpa dependensi) yang aman diimpor dari mana saja. Di
 * sini ada `prisma`, jadi modul ini WAJIB server-only — jangan digabung,
 * dan jangan diimpor dari komponen client.
 */
import { heroSlides as staticHeroSlides, type HeroSlide } from "@/data/heroSlides";
import { filterActiveSlides } from "@/lib/filterActiveSlides";
import { bannerLinkToHref } from "@/lib/home-banners";
import { prisma } from "@/lib/prisma";
import sharp from "sharp";

/**
 * Batas jumlah banner. Hero carousel berotasi 3 detik sekali — lebih dari
 * ini tidak pernah dilihat user, dan query halaman depan harus tetap
 * terbatas (lihat insiden query tanpa batas di halaman depan).
 */
const MAX_BANNERS = 10;

/**
 * Cadangan alt saat admin membiarkan `imageAlt` kosong (kolomnya
 * `@default("")`). Banner hero hampir selalu BERTAUT, dan gambar bertaut
 * dengan alt kosong membuat pengguna pembaca layar tidak tahu tautannya
 * menuju ke mana. Teks generik tetap lebih baik daripada kosong — tapi
 * yang benar adalah admin mengisi `imageAlt` per banner.
 */
const FALLBACK_ALT = "Banner promo Natalo Petshop";

/**
 * Ukuran gambar banner (w/h) per URL — memo per proses server. Kontainer
 * hero memakai rasio slide PERTAMA, jadi cukup satu pengukuran per
 * regenerasi halaman (ISR revalidate 60) + cache antar regenerasi.
 * Gagal (timeout, gambar rusak) → tanpa aspect → HeroBanner fallback 16/9.
 */
const dimensionMemo = new Map<string, { w: number; h: number }>();
const MEASURE_TIMEOUT_MS = 4000;
const MEASURE_MAX_BYTES = 5 * 1024 * 1024;

async function measureImageDimensions(
  url: string,
): Promise<{ w: number; h: number } | null> {
  const cached = dimensionMemo.get(url);
  if (cached) return cached;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(MEASURE_TIMEOUT_MS) });
    if (!res.ok) return null;
    const len = Number(res.headers.get("content-length") ?? 0);
    if (len > MEASURE_MAX_BYTES) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.byteLength > MEASURE_MAX_BYTES) return null;
    const meta = await sharp(buf).metadata();
    if (!meta.width || !meta.height) return null;
    const dim = { w: meta.width, h: meta.height };
    dimensionMemo.set(url, dim);
    return dim;
  } catch {
    return null;
  }
}

export async function loadHeroSlides(): Promise<HeroSlide[]> {
  try {
    const rows = await prisma.homeBanner.findMany({
      where: { isActive: true },
      orderBy: [{ position: "asc" }, { createdAt: "desc" }],
      take: MAX_BANNERS,
      select: {
        id: true,
        imageUrl: true,
        imageAlt: true,
        linkType: true,
        linkValue: true,
      },
    });

    if (rows.length > 0) {
      const slides: HeroSlide[] = rows.map((row, index) => {
        const href = bannerLinkToHref(row.linkType, row.linkValue);
        return {
          id: row.id,
          type: "image" as const,
          image: row.imageUrl,
          imageAlt: row.imageAlt.trim() || FALLBACK_ALT,
          // `href` optional di HeroSlide — hanya sertakan kalau banner
          // memang bisa di-tap (linkType "none" / value kosong → null).
          ...(href ? { href } : {}),
          // Slide pertama = elemen LCP halaman depan, muat eager. Sisanya
          // biarkan lazy supaya tidak ikut memperlambat first paint.
          priority: index === 0,
        };
      });

      // Rasio banner pertama menentukan aspect-ratio kontainer hero —
      // banner desain mobile (~2:1 untuk karosel app) tidak ter-crop
      // kiri-kanan di desktop (laporan 20 Sep 2026). Gagal ukur → slide
      // tanpa aspect → HeroBanner fallback 16/9.
      const firstImage = slides.find((s) => s.type === "image");
      if (firstImage && firstImage.type === "image") {
        const dim = await measureImageDimensions(firstImage.image);
        if (dim) firstImage.aspect = dim.w / dim.h;
      }

      return slides;
    }
  } catch {
    // DB error → jatuh ke slide statis di bawah. Hero lebih baik memakai
    // banner lama daripada hilang sama sekali.
  }

  return filterActiveSlides(staticHeroSlides);
}
