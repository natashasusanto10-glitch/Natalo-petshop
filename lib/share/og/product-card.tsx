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

export function renderProductShareCard(input: ProductShareCardInput) {
  const card = buildProductShareCardModel(input);
  const imageUrl = input.renderedImageUrl === undefined ? card.imageUrl : input.renderedImageUrl;

  return (
    <div
      style={{
        background: "#F8FAFC",
        color: "#10213D",
        display: "flex",
        fontFamily: "Arial, sans-serif",
        height: "100%",
        padding: 48,
        width: "100%",
      }}
    >
      <div
        style={{
          alignItems: "center",
          background: "#FFFFFF",
          borderRadius: 24,
          display: "flex",
          flex: 11,
          justifyContent: "center",
          overflow: "hidden",
          padding: 36,
        }}
      >
        {imageUrl ? (
          <img alt="" height="100%" src={imageUrl} style={{ height: "100%", objectFit: "contain", width: "100%" }} width="100%" />
        ) : (
          <div style={{ color: "#1E5FBF", display: "flex", fontSize: 140, fontWeight: 900 }}>N</div>
        )}
      </div>
      <div
        style={{
          background: "#0F2F63",
          borderRadius: 24,
          display: "flex",
          flex: 9,
          flexDirection: "column",
          justifyContent: "space-between",
          marginLeft: 28,
          padding: 44,
        }}
      >
        <div style={{ color: "#B9D4FF", display: "flex", fontSize: 24, fontWeight: 800 }}>
          NATALO PETSHOP
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          {card.discountLabel ? (
            <div style={{ background: "#F0446A", borderRadius: 10, color: "#FFFFFF", display: "flex", fontSize: 21, fontWeight: 800, padding: "9px 13px", width: "fit-content" }}>
              {card.discountLabel}
            </div>
          ) : null}
          <div style={{ WebkitBoxOrient: "vertical", WebkitLineClamp: 2, display: "-webkit-box", fontSize: 38, fontWeight: 800, lineHeight: 1.2, overflow: "hidden" }}>
            {card.name}
          </div>
          <div style={{ color: "#FFFFFF", display: "flex", fontSize: 44, fontWeight: 900 }}>
            {card.priceLabel}
          </div>
          {card.originalPriceLabel ? (
            <div style={{ color: "#B9D4FF", display: "flex", fontSize: 24, textDecoration: "line-through" }}>
              {card.originalPriceLabel}
            </div>
          ) : null}
        </div>
        <div style={{ color: "#DCEAFF", display: "flex", fontSize: 24, fontWeight: 700 }}>
          {card.stockLabel}
        </div>
      </div>
    </div>
  );
}
