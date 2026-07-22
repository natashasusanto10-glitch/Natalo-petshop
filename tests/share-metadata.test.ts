import assert from "node:assert/strict";
import test from "node:test";

import { buildFeedShareMetadata } from "@/lib/share/share-metadata";

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

  assert.match(String(metadata.title), /Postingan Natalo/);
  assert.match(String(metadata.description), /Natalo Petshop/);
  assert.deepEqual(metadata.robots, { index: true, follow: true });
});
