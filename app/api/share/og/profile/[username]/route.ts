import { ImageResponse } from "next/og";
import { NextResponse } from "next/server";

import { renderProfileShareCard } from "@/lib/share/og/profile-card";
import { fetchSafeOgImageData, resolveOgImageCachePolicy } from "@/lib/share/og-image-security";
import { getPublicShareProfile } from "@/lib/share/profile-share-data";

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
  { params }: { params: Promise<{ username: string }> },
) {
  const { username } = await params;
  const profile = await getPublicShareProfile(username);
  if (!profile) return new NextResponse(null, { status: 404 });

  const cachePolicy = resolveOgImageCachePolicy(
    new URL(request.url).searchParams.get("v"),
    profile.shareVersion,
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
    const renderedAvatarUrl = await fetchSafeOgImageData(publicImageUrl(profile.avatarUrl));
    return new ImageResponse(renderProfileShareCard({ ...profile, renderedAvatarUrl }), {
      ...IMAGE_OPTIONS,
      headers,
    });
  } catch (error) {
    console.error("profile_share_og_render_failed", { username, error });
    return new ImageResponse(renderProfileShareCard({ ...profile, renderedAvatarUrl: null }), {
      ...IMAGE_OPTIONS,
      headers,
    });
  }
}
