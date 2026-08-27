import assert from "node:assert/strict";
import test from "node:test";

import {
  buildFeedShareMetadata,
  buildUnavailableFeedShareMetadata,
} from "@/lib/share/share-metadata";
import PublicFeedPostPage, {
  dynamic,
  revalidate,
} from "@/app/feed/[id]/page";
import { prisma } from "@/lib/prisma";

const siteUrl = "https://www.natalopetshop.com";

test("Feed metadata uses canonical without v and versioned OG image", () => {
  const metadata = buildFeedShareMetadata(
    {
      id: "post/1",
      shareVersion: "preview-v1",
      title: "Makanan kucing premium",
      description: "Diskon untuk makanan kucing pilihan.",
      author: {
        displayName: "Natalo Petshop",
        photoUrl: null,
        username: "natalopetshop",
        isOfficial: true,
      },
      posterUrl: "https://cdn.example.com/poster.jpg",
    },
    siteUrl,
  );

  assert.equal(metadata.alternates?.canonical, `${siteUrl}/feed/post%2F1`);
  assert.equal(metadata.openGraph?.url, `${siteUrl}/feed/post%2F1`);
  const images = metadata.openGraph?.images;
  assert.ok(Array.isArray(images));
  const firstImage = images[0];
  assert.equal(
    typeof firstImage === "string"
      ? firstImage
      : firstImage instanceof URL
        ? firstImage.toString()
        : firstImage?.url,
    `${siteUrl}/api/share/og/feed/post%2F1?v=preview-v1`,
  );
  assert.ok(metadata.twitter && "card" in metadata.twitter);
  assert.equal(metadata.twitter.card, "summary_large_image");
  // Judul link = caption postingan: kartu OG full-bleed tidak menggambar
  // teks di atas thumbnail, jadi baris judul satu-satunya tempat caption.
  assert.equal(metadata.title, "Diskon untuk makanan kucing pilihan.");
  assert.equal(metadata.openGraph?.title, "Diskon untuk makanan kucing pilihan.");
  assert.equal(metadata.description, "Postingan Natalo Petshop di Natalo Petshop.");
  const firstOgImage = images[0];
  if (typeof firstOgImage === "object" && !(firstOgImage instanceof URL)) {
    // WAJIB persegi + sinkron dengan IMAGE_OPTIONS di route OG feed.
    assert.equal(firstOgImage.width, 1200);
    assert.equal(firstOgImage.height, 1200);
  } else {
    assert.fail("og:image feed harus objek dengan width/height eksplisit");
  }
});

test("Feed metadata tanpa caption memakai judul postingan, lalu fallback author", () => {
  const base = {
    id: "post-2",
    shareVersion: "v1",
    author: {
      displayName: "Natalo Petshop",
      photoUrl: null,
      username: "natalopetshop",
      isOfficial: true,
    },
    posterUrl: null,
  };

  // description kosong -> pakai title (judul postingan).
  const withTitle = buildFeedShareMetadata(
    { ...base, title: "Makanan kucing premium", description: "" },
    siteUrl,
  );
  assert.equal(withTitle.title, "Makanan kucing premium");
});

test("Feed metadata has stable safe fallback copy and public robots", () => {
  const metadata = buildFeedShareMetadata(
    {
      id: "post-1",
      shareVersion: "v1",
      title: "",
      description: "",
      author: {
        displayName: "",
        photoUrl: null,
        username: null,
        isOfficial: false,
      },
      posterUrl: null,
    },
    siteUrl,
  );

  // Tanpa caption DAN tanpa judul: kartu tetap tidak boleh tanpa teks.
  assert.equal(metadata.title, "Postingan Natalo Petshop di Natalo");
  assert.match(String(metadata.description), /Lihat postingan terbaru dari Natalo Petshop di Natalo/);
  assert.deepEqual(metadata.robots, { index: true, follow: true });
});

test("unavailable Feed metadata is noindex and does not leak private post data", () => {
  const metadata = buildUnavailableFeedShareMetadata();
  const serialized = JSON.stringify(metadata);

  assert.deepEqual(metadata.robots, { index: false, follow: false });
  assert.doesNotMatch(serialized, /draft author|private caption|private-media/i);
});

test("Feed share page is dynamic so a new v URL cannot reuse stale metadata", () => {
  assert.equal(dynamic, "force-dynamic");
  assert.equal(revalidate, 0);
});

test("public Feed page becomes a Next 404 when the public post cannot resolve", async () => {
  const feedPost = prisma.feedPost as unknown as {
    findFirst: typeof prisma.feedPost.findFirst;
  };
  const originalFindFirst = feedPost.findFirst;
  feedPost.findFirst = (async () => null) as typeof feedPost.findFirst;

  try {
    await assert.rejects(
      () => PublicFeedPostPage({ params: Promise.resolve({ id: "private-post" }) }),
      (error: { digest?: string }) =>
        error.digest === "NEXT_HTTP_ERROR_FALLBACK;404" ||
        error.digest === "NEXT_NOT_FOUND",
    );
  } finally {
    feedPost.findFirst = originalFindFirst;
  }
});
