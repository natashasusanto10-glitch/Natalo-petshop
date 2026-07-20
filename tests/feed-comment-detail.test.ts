import assert from "node:assert/strict";
import test from "node:test";
import { getFeedCommentDetail } from "@/lib/feed/queries";

function baseComment(overrides: Record<string, unknown> = {}) {
  return {
    id: "c1",
    postId: "p1",
    parentCommentId: null,
    content: "halo",
    deletedAt: null,
    isAdminOfficial: false,
    isHidden: false,
    likeCount: 2,
    createdAt: new Date("2026-07-20T00:00:00Z"),
    author: {
      id: "u1",
      name: "Asiong",
      username: "asiong",
      role: "CUSTOMER",
      profilePhotoUrl: "https://cdn/asiong.jpg",
    },
    replies: [],
    post: { status: "ACTIVE", deletedAt: null },
    ...overrides,
  };
}

function makeDb(comment: unknown, likes: Array<{ commentId: string }> = []) {
  return {
    feedComment: { async findUnique() { return comment; } },
    feedCommentLike: { async findMany() { return likes; } },
    user: { async findMany() { return []; } },
  } as never;
}

test("ok: komentar customer + viewerLiked dari likes", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    viewerUserId: "viewer",
    db: makeDb(baseComment(), [{ commentId: "c1" }]),
  });
  assert.equal(res.status, "ok");
  if (res.status !== "ok") return;
  assert.equal(res.comment.id, "c1");
  assert.equal(res.comment.postId, "p1");
  assert.equal(res.comment.author.username, "asiong");
  assert.equal(res.comment.author.name, "Asiong");
  assert.equal(res.comment.viewerLiked, true);
});

test("ok: viewerLiked false saat anonim (tanpa viewerUserId)", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment()),
  });
  assert.equal(res.status, "ok");
  if (res.status !== "ok") return;
  assert.equal(res.comment.viewerLiked, false);
});

test("brand-safe: author admin → nama brand + foto null", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(
      baseComment({
        author: {
          id: "admin1",
          name: "Private Owner",
          username: "natalopetshop",
          role: "ADMIN",
          profilePhotoUrl: "https://cdn/private.jpg",
        },
      }),
    ),
  });
  assert.equal(res.status, "ok");
  if (res.status !== "ok") return;
  assert.equal(res.comment.author.name, "Natalo Petshop Official");
  assert.equal(res.comment.author.profilePhotoUrl, null);
});

test("not-found: komentar tidak ada", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(null),
  });
  assert.equal(res.status, "not-found");
});

test("not-found: komentar soft-deleted", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ deletedAt: new Date() })),
  });
  assert.equal(res.status, "not-found");
});

test("not-found: komentar hidden (moderasi)", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ isHidden: true })),
  });
  assert.equal(res.status, "not-found");
});

test("not-found: reply whose parent (root comment) has been hidden by moderation", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(
      baseComment({
        parentCommentId: "root1",
        parent: { isHidden: true },
      }),
    ),
  });
  assert.equal(res.status, "not-found");
});

test("ok: reply whose parent (root comment) is merely deleted-not-hidden stays visible", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(
      baseComment({
        parentCommentId: "root1",
        parent: { isHidden: false, deletedAt: new Date() },
      }),
    ),
  });
  assert.equal(res.status, "ok");
});

test("post-gone: post induk deletedAt", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ post: { status: "ACTIVE", deletedAt: new Date() } })),
  });
  assert.equal(res.status, "post-gone");
});

test("post-gone: post status bukan ACTIVE", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ post: { status: "PENDING_REVIEW", deletedAt: null } })),
  });
  assert.equal(res.status, "post-gone");
});
