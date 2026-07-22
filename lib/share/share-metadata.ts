import type { Metadata } from "next";

import type { PublicShareFeedPost } from "./feed-share-data";

const brandName = "Natalo Petshop";

function publicUrl(siteUrl: string, path: string) {
  return new URL(path, siteUrl).toString();
}

function cleanCopy(value: string | null | undefined, limit: number) {
  return (value ?? "").replace(/\s+/g, " ").trim().slice(0, limit);
}

/** Metadata shared by the Feed page and its explicit image generator route. */
export function buildFeedShareMetadata(
  post: Pick<
    PublicShareFeedPost,
    "id" | "shareVersion" | "title" | "description" | "author" | "posterUrl"
  >,
  siteUrl: string,
): Metadata {
  const postPath = `/feed/${encodeURIComponent(post.id)}`;
  const canonical = publicUrl(siteUrl, postPath);
  const title = cleanCopy(post.title, 90) || "Postingan Natalo";
  const author = cleanCopy(post.author.displayName, 80) || brandName;
  const description =
    cleanCopy(post.description, 140) || `Lihat postingan ${author} di ${brandName}.`;
  const ogImage = publicUrl(
    siteUrl,
    `/api/share/og/feed/${encodeURIComponent(post.id)}?v=${encodeURIComponent(post.shareVersion)}`,
  );

  return {
    title: `${title} | ${brandName}`,
    description,
    alternates: { canonical },
    robots: { index: true, follow: true },
    openGraph: {
      type: "article",
      title: `${title} | ${brandName}`,
      description,
      url: canonical,
      siteName: brandName,
      images: [{ url: ogImage, width: 1200, height: 630, alt: title }],
    },
    twitter: {
      card: "summary_large_image",
      title: `${title} | ${brandName}`,
      description,
      images: [ogImage],
    },
  };
}
