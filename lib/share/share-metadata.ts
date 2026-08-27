import type { Metadata } from "next";

import type { PublicShareFeedPost } from "./feed-share-data";

const brandName = "Natalo Petshop";

function publicUrl(siteUrl: string, path: string) {
  return new URL(path, siteUrl).toString();
}

function cleanCopy(value: string | null | undefined, limit: number) {
  return (value ?? "").replace(/\s+/g, " ").trim().slice(0, limit);
}

export function buildUnavailableFeedShareMetadata(): Metadata {
  return {
    title: "Postingan tidak ditemukan | Natalo Petshop",
    description: "Postingan yang Anda cari tidak tersedia.",
    robots: { index: false, follow: false },
  };
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
  const author = cleanCopy(post.author.displayName, 80) || brandName;
  // Judul link = CAPTION postingan, bukan "<author> di Natalo": kartu OG
  // full-bleed sudah tidak menggambar teks apa pun di atas thumbnail,
  // jadi baris judul di bawah gambar adalah satu-satunya tempat caption
  // terbaca. Nama author turun ke description; tanpa caption sama sekali,
  // jatuh kembali ke bentuk lama supaya kartu tidak pernah tanpa judul.
  const caption = cleanCopy(post.description, 120) || cleanCopy(post.title, 120);
  const title = caption || `Postingan ${author} di Natalo`;
  const description = caption
    ? `Postingan ${author} di Natalo Petshop.`
    : `Lihat postingan terbaru dari ${author} di Natalo.`;
  const ogImage = publicUrl(
    siteUrl,
    `/api/share/og/feed/${encodeURIComponent(post.id)}?v=${encodeURIComponent(post.shareVersion)}`,
  );

  return {
    title,
    description,
    alternates: { canonical },
    robots: { index: true, follow: true },
    openGraph: {
      type: "article",
      title,
      description,
      url: canonical,
      siteName: brandName,
      // WAJIB sinkron dengan IMAGE_OPTIONS di
      // app/api/share/og/feed/[id]/route.ts — kartu feed sengaja PERSEGI
      // supaya thumbnail video tampil besar di iMessage/WhatsApp.
      images: [{ url: ogImage, width: 1200, height: 1200, alt: author }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [ogImage],
    },
  };
}
