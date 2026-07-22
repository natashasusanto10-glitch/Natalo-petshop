import { ImageResponse } from "next/og";
import { NextResponse } from "next/server";

import { getPublicShareFeedPost } from "@/lib/share/feed-share-data";
import { renderFeedShareCard } from "@/lib/share/og/feed-card";
import { fetchSafeOgImageData } from "@/lib/share/og-image-security";

export const runtime = "nodejs";

const IMAGE_OPTIONS = { height: 630, width: 1200 } as const;
const CACHE_HEADERS = {
  "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
};

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const post = await getPublicShareFeedPost(id);
  if (!post) return new NextResponse(null, { status: 404 });

  try {
    const [renderedMediaUrl, renderedAuthorImageUrl] = await Promise.all([
      fetchSafeOgImageData(post.posterUrl),
      fetchSafeOgImageData(post.author.photoUrl),
    ]);
    return new ImageResponse(renderFeedShareCard({
      ...post,
      renderedAuthorImageUrl,
      renderedMediaUrl,
    }), {
      ...IMAGE_OPTIONS,
      headers: CACHE_HEADERS,
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
      headers: CACHE_HEADERS,
    });
  }
}
