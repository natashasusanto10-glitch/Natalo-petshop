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
 * Kartu pratinjau berbagi produk — foto produk memenuhi kartu.
 *
 * Layout lama membelah kartu jadi dua: foto di kiri, panel biru berisi nama +
 * harga + stok di kanan. Dua masalah:
 *
 * 1. BUG KONTRAS. Nama produk tidak diberi warna sendiri, jadi mewarisi
 *    #10213D dari elemen induk dan tampil di atas panel #0F2F63 — kontrasnya
 *    1,23:1 (minimum layak baca 3:1), praktis tak terbaca. Diukur langsung
 *    dari gambar produksi. Karena itu SEMUA teks di sini diberi warna
 *    eksplisit; jangan pernah mengandalkan warna warisan di kartu OG.
 *
 * 2. Separuh kartu terpakai teks yang sebetulnya mubazir: Instagram/WhatsApp
 *    sudah menampilkan judul dan deskripsi sendiri di bawah kartu. Nama dan
 *    label stok karena itu dibuang dari gambar (tetap ada di model, dipakai
 *    metadata halaman), menyisakan foto produk sebagai bintangnya.
 *
 * Yang tersisa di atas foto hanya dua penanda kecil: chip merek di kiri-atas
 * dan harga di kanan-bawah (plus badge diskon kalau ada).
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
          padding: 40,
          width: "100%",
        }}
      >
        {imageUrl ? (
          // contain, bukan cover: foto produk umumnya 1:1 sedangkan kartu
          // 1200x630 — cover akan memotong atas-bawah produknya.
          <img alt="" height="100%" src={imageUrl} style={{ height: "100%", objectFit: "contain", width: "100%" }} width="100%" />
        ) : (
          <div style={{ color: "#1E5FBF", display: "flex", fontSize: 160, fontWeight: 900 }}>N</div>
        )}
      </div>

      <div
        style={{
          alignItems: "center",
          background: "#1E5FBF",
          borderRadius: 999,
          color: "#FFFFFF",
          display: "flex",
          fontSize: 26,
          fontWeight: 800,
          left: 44,
          padding: "13px 26px",
          position: "absolute",
          top: 40,
        }}
      >
        Natalo Petshop
      </div>

      <div
        style={{
          alignItems: "center",
          bottom: 40,
          display: "flex",
          position: "absolute",
          right: 44,
        }}
      >
        {card.discountLabel ? (
          <div
            style={{
              alignItems: "center",
              background: "#F0446A",
              borderRadius: 999,
              color: "#FFFFFF",
              display: "flex",
              fontSize: 24,
              fontWeight: 800,
              marginRight: 12,
              padding: "12px 22px",
            }}
          >
            {card.discountLabel}
          </div>
        ) : null}
        <div
          style={{
            alignItems: "center",
            background: "#0A1F40",
            borderRadius: 999,
            color: "#FFFFFF",
            display: "flex",
            fontSize: 38,
            fontWeight: 900,
            padding: "14px 30px",
          }}
        >
          {card.priceLabel}
        </div>
      </div>
    </div>
  );
}
