import type { Metadata } from "next";

import { formatRupiah } from "@/lib/format";
import { getProductBySlug, type StoreProduct } from "@/lib/products";
import { prisma } from "@/lib/prisma";

import { buildShareVersion, stripEphemeralUrlQuery } from "./share-version";

const BRAND_NAME = "Natalo Petshop";

export type PublicShareProduct = {
  id: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  effectivePrice: number;
  originalPrice: number | null;
  discountPercent: number | null;
  shareVersion: string;
  stockLabel: string;
};

export type ProductShareSource = Pick<
  StoreProduct,
  "id" | "slug" | "name" | "price" | "discountPrice" | "stock" | "imageUrl"
>;

type ProductLookup = (slug: string) => Promise<StoreProduct | null>;
type ProductVisibilityRepository = Pick<typeof prisma, "product">;

function cleanPublicText(value: string | null | undefined, limit: number) {
  const clean = (value ?? "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return clean.length > limit ? `${clean.slice(0, limit - 1).trimEnd()}…` : clean;
}

function stripAssetQuery(value: string | null | undefined) {
  const asset = stripEphemeralUrlQuery(value);
  return asset.split("?")[0]?.split("#")[0] ?? "";
}

export function productStockLabel(stock: number) {
  if (stock <= 0) return "Stok habis";
  if (stock <= 5) return "Stok terbatas";
  return "Stok tersedia";
}

/** Converts the existing customer-facing product price into public share data. */
export function buildPublicShareProduct(product: ProductShareSource | null): PublicShareProduct | null {
  if (!product) return null;

  const basePrice = Math.max(0, Math.trunc(product.price));
  const discountedPrice = product.discountPrice;
  const hasActiveDiscount =
    discountedPrice !== null && discountedPrice > 0 && discountedPrice < basePrice;
  const effectivePrice = hasActiveDiscount ? discountedPrice : basePrice;
  const originalPrice = hasActiveDiscount ? basePrice : null;
  const discountPercent = originalPrice
    ? Math.round(((originalPrice - effectivePrice) / originalPrice) * 100)
    : null;
  const name = cleanPublicText(product.name, 180) || "Produk Natalo";
  const imageUrl = product.imageUrl ? stripAssetQuery(product.imageUrl) || null : null;
  const stockLabel = productStockLabel(Math.max(0, Math.trunc(product.stock)));

  return {
    id: product.id,
    slug: product.slug,
    name,
    imageUrl,
    effectivePrice,
    originalPrice,
    discountPercent,
    stockLabel,
    shareVersion: buildShareVersion([
      product.slug,
      name,
      imageUrl,
      effectivePrice,
      originalPrice,
      discountPercent,
      stockLabel,
    ]),
  };
}

/**
 * Resolves a shareable product through the existing customer price resolver,
 * then applies the production visibility gate before any preview data leaves
 * the server.
 */
export async function getPublicShareProduct(
  rawSlug: string,
  lookup: ProductLookup = getProductBySlug,
  repository: ProductVisibilityRepository = prisma,
): Promise<PublicShareProduct | null> {
  const slug = rawSlug.trim();
  if (!slug) return null;

  const product = await lookup(slug);
  if (!product) return null;

  const visible = await repository.product.findFirst({
    where: { id: product.id, isActive: true, creationState: "ready" },
    select: { id: true },
  });
  if (!visible) return null;

  return buildPublicShareProduct(product);
}

function publicUrl(siteUrl: string, path: string) {
  return new URL(path, siteUrl).toString();
}

export function buildUnavailableProductShareMetadata(): Metadata {
  return {
    title: "Produk tidak ditemukan | Natalo Petshop",
    description: "Produk yang Anda cari tidak tersedia.",
    robots: { index: false, follow: false },
  };
}

export function buildProductShareMetadata(product: PublicShareProduct, siteUrl: string): Metadata {
  const path = `/products/${encodeURIComponent(product.slug)}`;
  const canonical = publicUrl(siteUrl, path);
  const title = `${product.name} | ${BRAND_NAME}`;
  const description = `${formatRupiah(product.effectivePrice)} - ${product.stockLabel}. Produk original ${BRAND_NAME}.`;
  const image = publicUrl(
    siteUrl,
    `/api/share/og/product/${encodeURIComponent(product.slug)}?v=${encodeURIComponent(product.shareVersion)}`,
  );

  return {
    title,
    description,
    alternates: { canonical },
    robots: { index: true, follow: true },
    openGraph: {
      type: "website",
      title,
      description,
      url: canonical,
      siteName: BRAND_NAME,
      // WAJIB sinkron dengan IMAGE_OPTIONS di
      // app/api/share/og/product/[slug]/route.ts — kartu produk sengaja
      // PERSEGI supaya foto tampil besar di iMessage/WhatsApp.
      images: [{ url: image, width: 1200, height: 1200, alt: product.name }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [image],
    },
  };
}
