import type { PublicShareProduct } from "@/lib/share/product-share-data";
import { formatRupiah } from "@/lib/format";

import { safeOgImageUrl } from "../og-image-security";

export type ProductShareCardInput = PublicShareProduct & {
  renderedImageUrl?: string | null;
};

export type ProductShareCardModel = {
  discountLabel: string | null;
  imageUrl: string | null;
  name: string;
  originalPriceLabel: string | null;
  priceLabel: string;
  stockLabel: string;
};

function cleanName(value: string) {
  const clean = value.replace(/[\u0000-\u001F\u007F]/g, " ").replace(/\s+/g, " ").trim();
  return clean.length > 110 ? `${clean.slice(0, 109).trimEnd()}…` : clean || "Produk Natalo";
}

export function buildProductShareCardModel(input: ProductShareCardInput): ProductShareCardModel {
  return {
    discountLabel: input.discountPercent ? `HEMAT ${input.discountPercent}%` : null,
    imageUrl: safeOgImageUrl(input.imageUrl),
    name: cleanName(input.name),
    originalPriceLabel: input.originalPrice ? formatRupiah(input.originalPrice) : null,
    priceLabel: formatRupiah(input.effectivePrice),
    stockLabel: input.stockLabel,
  };
}

/**
 * Kartu pratinjau berbagi produk — foto produk FULL-BLEED di kanvas persegi.
 *
 * Sejarah tiga tahap, supaya tidak ada yang mengulang langkah mundur:
 *
 * 1. Layout paling awal membelah kartu: foto di kiri, panel biru berisi nama
 *    + harga + stok di kanan. BUG KONTRAS: nama produk tidak diberi warna
 *    sendiri, jadi mewarisi #10213D dan tampil di atas panel #0F2F63 —
 *    kontras 1,23:1 (minimum layak baca 3:1), praktis tak terbaca. Diukur
 *    dari gambar produksi. Karena itu SEMUA teks di berkas ini WAJIB punya
 *    warna eksplisit; jangan pernah mengandalkan warna warisan di kartu OG.
 *
 * 2. Lalu foto dibuat memenuhi kartu 1200x630, menyisakan chip merek di
 *    kiri-atas dan chip harga di kanan-bawah. Masih kalah jelas dari Shopee:
 *    kanvas landscape membuat iMessage/WhatsApp menggambar kartu PENDEK, dan
 *    foto produk 1:1 menyusut ke ~550px diapit dua bidang putih lebar.
 *
 * 3. Sekarang: kanvas PERSEGI 1200x1200, padding nol, tanpa chip apa pun.
 *
 * Kenapa chip dibuang — dibuktikan lewat render mockup, bukan dugaan:
 * - Chip merek MUBAZIR. Foto template katalog ini sudah memuat pita
 *   "Natalo Petshop & Aquarium · OFFICIAL STORE" yang jauh lebih bagus;
 *   chip justru menimpanya.
 * - Chip harga SELALU menabrak isi foto. Template memakai keempat sudut
 *   untuk badge (varian, Grain Free, No Pork, "1/6") — tidak ada sudut
 *   aman. Harga tetap terbaca: klien chat menampilkannya di teks di bawah
 *   kartu, dari `description` metadata halaman.
 *
 * `buildProductShareCardModel` SENGAJA dipertahankan lengkap (nama, harga,
 * diskon, stok) walau gambar tidak memakainya — model itu dipakai metadata
 * halaman dan diuji terpisah.
 *
 * TETAP objectFit contain, JANGAN cover: foto non-1:1 akan terpotong tepat
 * di pita atas dan banner bawah template toko.
 */
export function renderProductShareCard(input: ProductShareCardInput) {
  const card = buildProductShareCardModel(input);
  const imageUrl = input.renderedImageUrl === undefined ? card.imageUrl : input.renderedImageUrl;

  return (
    <div
      style={{
        background: "#FFFFFF",
        display: "flex",
        fontFamily: "Arial, sans-serif",
        height: "100%",
        position: "relative",
        width: "100%",
      }}
    >
      <div
        style={{
          alignItems: "center",
          display: "flex",
          height: "100%",
          justifyContent: "center",
          width: "100%",
        }}
      >
        {imageUrl ? (
          <img alt="" height="100%" src={imageUrl} style={{ height: "100%", objectFit: "contain", width: "100%" }} width="100%" />
        ) : (
          // Fallback saat foto gagal diambil — huruf N besar di kanvas
          // persegi, warna eksplisit (lihat catatan bug kontras di atas).
          <div style={{ color: "#1E5FBF", display: "flex", fontSize: 300, fontWeight: 900 }}>N</div>
        )}
      </div>
    </div>
  );
}
