import { ImageResponse } from "next/og";
import { NextResponse } from "next/server";

import { getPublicShareProduct } from "@/lib/share/product-share-data";
import { renderProductShareCard } from "@/lib/share/og/product-card";
import { fetchSafeOgImageData, resolveOgImageCachePolicy } from "@/lib/share/og-image-security";

export const runtime = "nodejs";

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || "https://www.natalopetshop.com";
const IMAGE_OPTIONS = { height: 630, width: 1200 } as const;

function publicImageUrl(value: string | null) {
  if (!value) return null;
  try {
    return new URL(value, SITE_URL).toString();
  } catch {
    return null;
  }
}

export async function GET(
  request: Request,
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const product = await getPublicShareProduct(slug);
  if (!product) return new NextResponse(null, { status: 404 });

  const cachePolicy = resolveOgImageCachePolicy(
    new URL(request.url).searchParams.get("v"),
    product.shareVersion,
  );
  if (cachePolicy.redirectToVersion) {
    const redirectUrl = new URL(request.url);
    redirectUrl.search = `v=${encodeURIComponent(cachePolicy.redirectToVersion)}`;
    return NextResponse.redirect(redirectUrl, {
      headers: { "Cache-Control": cachePolicy.cacheControl },
      status: 307,
    });
  }

  const headers = { "Cache-Control": cachePolicy.cacheControl };
  try {
    const renderedImageUrl = await fetchSafeOgImageData(publicImageUrl(product.imageUrl));
    return new ImageResponse(renderProductShareCard({ ...product, renderedImageUrl }), {
      ...IMAGE_OPTIONS,
      headers,
    });
  } catch (error) {
    console.error("product_share_og_render_failed", { slug, error });
    return new ImageResponse(renderProductShareCard({ ...product, renderedImageUrl: null }), {
      ...IMAGE_OPTIONS,
      headers,
    });
  }
}
