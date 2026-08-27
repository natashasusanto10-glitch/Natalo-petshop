import { ImageResponse } from "next/og";
import { NextResponse } from "next/server";

import { getPublicShareFeedPost } from "@/lib/share/feed-share-data";
import { renderFeedShareCard } from "@/lib/share/og/feed-card";
import {
  fetchSafeOgImageData,
  resolveOgImageCachePolicy,
} from "@/lib/share/og-image-security";

export const runtime = "nodejs";

// PERSEGI, sama dengan kartu produk: iMessage/WhatsApp menentukan TINGGI
// kartu dari rasio gambar, jadi 1200x630 selalu menghasilkan kartu pendek
// dengan thumbnail kecil. WAJIB sinkron dengan width/height og:image di
// lib/share/share-metadata.ts — kalau salah satu diubah sendirian, klien
// chat menata kartu dengan rasio salah tanpa error apa pun.
const IMAGE_OPTIONS = { height: 1200, width: 1200 } as const;
export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const post = await getPublicShareFeedPost(id);
  if (!post) return new NextResponse(null, { status: 404 });

  const cachePolicy = resolveOgImageCachePolicy(
    new URL(request.url).searchParams.get("v"),
    post.shareVersion,
  );
  if (cachePolicy.redirectToVersion) {
    const redirectUrl = new URL(request.url);
    redirectUrl.search = `v=${encodeURIComponent(cachePolicy.redirectToVersion)}`;
    return NextResponse.redirect(redirectUrl, {
      headers: { "Cache-Control": cachePolicy.cacheControl },
      status: 307,
    });
  }
  const responseHeaders = { "Cache-Control": cachePolicy.cacheControl };

  try {
    // Foto author tidak lagi diambil — kartu full-bleed tidak
    // menggambarnya, jadi fetch-nya cuma menambah latensi render.
    const renderedMediaUrl = await fetchSafeOgImageData(post.posterUrl);
    return new ImageResponse(renderFeedShareCard({
      ...post,
      renderedAuthorImageUrl: null,
      renderedMediaUrl,
    }), {
      ...IMAGE_OPTIONS,
      headers: responseHeaders,
    });
  } catch (error) {
    console.error("feed_share_og_render_failed", { postId: id, error });
    // A malformed remote asset must never turn a public preview into a 500.
    return new ImageResponse(renderFeedShareCard({
      ...post,
      posterUrl: null,
      renderedAuthorImageUrl: null,
      renderedMediaUrl: null,
    }), {
      ...IMAGE_OPTIONS,
      headers: responseHeaders,
    });
  }
}
