import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

import {
  buildFeedShareVersion,
  getPublicShareFeedPost,
  PUBLIC_SHARE_FEED_POST_WHERE,
  type PublicShareFeedPostRepository,
} from "@/lib/share/feed-share-data";

const carouselVersionInput = {
  id: "carousel-post",
  title: "Produk pilihan",
  description: "Lihat koleksi terbaru",
  thumbnailUrl: null,
  videoDurationSec: null,
  author: {
    role: "MEMBER",
    name: "Natalo Member",
    profilePhotoUrl: null,
  },
  authorRole: "MEMBER",
};

test("shareVersion carousel mengikuti media poster pertama, bukan query CDN sementara", () => {
  const first = buildFeedShareVersion({
    ...carouselVersionInput,
    media: [
      {
        url: "https://cdn.example.com/carousel-a.jpg?token=old&expires=1",
        thumbnailUrl: null,
      },
    ],
  });
  const resignedFirst = buildFeedShareVersion({
    ...carouselVersionInput,
    media: [
      {
        url: "https://cdn.example.com/carousel-a.jpg?token=new&expires=2",
        thumbnailUrl: null,
      },
    ],
  });
  const replacedFirst = buildFeedShareVersion({
    ...carouselVersionInput,
    media: [
      {
        url: "https://cdn.example.com/carousel-b.jpg?token=new&expires=2",
        thumbnailUrl: null,
      },
    ],
  });

  assert.equal(first, resignedFirst);
  assert.notEqual(first, replacedFirst);
});

test("detail Feed API delegates carousel preview version to the shared helper", () => {
  const routeSource = readFileSync(
    resolve(process.cwd(), "app/api/feed/posts/[id]/route.ts"),
    "utf8",
  );

  assert.match(
    routeSource,
    /import\s*\{\s*buildFeedShareVersion\s*\}\s*from\s*["']@\/lib\/share\/feed-share-data["']/,
  );
  assert.match(routeSource, /shareVersion:\s*buildFeedShareVersion\(post\)/);
  assert.match(
    routeSource,
    /media:\s*\{\s*orderBy:\s*\{\s*sortOrder:\s*["']asc["']\s*\}/,
  );
});

test("public share Feed query always restricts to active, non-deleted posts", () => {
  assert.equal(PUBLIC_SHARE_FEED_POST_WHERE.status, "ACTIVE");
  assert.equal(PUBLIC_SHARE_FEED_POST_WHERE.deletedAt, null);
  assert.equal(PUBLIC_SHARE_FEED_POST_WHERE.encodingStatus, "ready");
});

type Candidate = {
  status: string;
  deletedAt: Date | null;
  encodingStatus: string;
};

function repositoryFor(candidate: Candidate): PublicShareFeedPostRepository {
  const privateRecord = {
    id: "private-post",
    title: "private caption",
    description: "private caption with private-media",
    kind: "PHOTO_CAROUSEL",
    thumbnailUrl: "https://cdn.example.com/private-media.jpg",
    videoUrl: null,
    videoDurationSec: null,
    productId: null,
    status: candidate.status,
    deletedAt: candidate.deletedAt,
    encodingStatus: candidate.encodingStatus,
    authorRole: "MEMBER",
    author: {
      name: "draft author",
      username: "private-user",
      role: "MEMBER",
      profilePhotoUrl: null,
    },
    media: [],
  };

  return {
    feedPost: {
      // Deliberately returns a private row even if a future query regresses.
      // The share helper must keep a final visibility gate before serialization.
      findFirst: async () => privateRecord,
    },
  } as unknown as PublicShareFeedPostRepository;
}

for (const candidate of [
  { status: "DRAFT", deletedAt: null, encodingStatus: "ready" },
  { status: "REJECTED", deletedAt: null, encodingStatus: "ready" },
  { status: "ACTIVE", deletedAt: new Date(), encodingStatus: "ready" },
  { status: "ACTIVE", deletedAt: null, encodingStatus: "processing" },
]) {
  test(`non-public Feed ${candidate.status}/${candidate.encodingStatus} resolves to null without leaking data`, async () => {
    const result = await getPublicShareFeedPost(
      "private-post",
      repositoryFor(candidate),
    );

    assert.equal(result, null);
    assert.doesNotMatch(JSON.stringify(result), /draft author|private caption|private-media/i);
  });
}
