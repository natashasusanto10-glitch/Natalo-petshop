import assert from "node:assert/strict";
import test from "node:test";

import {
  getPublicShareFeedPost,
  PUBLIC_SHARE_FEED_POST_WHERE,
  type PublicShareFeedPostRepository,
} from "@/lib/share/feed-share-data";

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
