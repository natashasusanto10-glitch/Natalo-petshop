import assert from "node:assert/strict";
import test from "node:test";
import {
  prepareFeedStateForAccountDeletion,
  reconcileFeedStateAfterAccountHardDelete,
} from "@/lib/feed/comment-account-delete";

type CapturedSql = { sql: string; values: unknown[] };

test("account deletion freezes the User and locks every affected post in stable order", async () => {
  const lockQueries: CapturedSql[] = [];
  const db = {
    feedComment: {
      async findMany() {
        return [
          { postId: "post-z" },
          { postId: "post-a" },
          { postId: "post-z" },
        ];
      },
    },
    feedLike: {
      async findMany() {
        return [{ postId: "post-b" }, { postId: "post-b" }];
      },
    },
    feedCommentLike: {
      async findMany() {
        return [
          { commentId: "comment-z", comment: { postId: "post-c" } },
          { commentId: "comment-a", comment: { postId: "post-a" } },
        ];
      },
    },
    async $queryRaw(query: CapturedSql) {
      lockQueries.push(query);
      return lockQueries.length === 1 ? [{ id: "user-1" }] : [];
    },
    async $executeRaw() {
      return 0;
    },
  };

  const impact = await prepareFeedStateForAccountDeletion({
    db: db as never,
    userId: "user-1",
  });

  assert.deepEqual(impact, {
    commentPostIds: ["post-a", "post-z"],
    likedPostIds: ["post-b"],
    likedCommentIds: ["comment-a", "comment-z"],
  });
  assert.equal(lockQueries.length, 2);
  assert.match(lockQueries[0].sql, /FROM "User"[\s\S]+FOR UPDATE/);
  assert.deepEqual(lockQueries[0].values, ["user-1"]);
  assert.match(
    lockQueries[1].sql,
    /FROM "FeedPost"[\s\S]+ORDER BY "id"[\s\S]+FOR UPDATE/
  );
  assert.deepEqual(lockQueries[1].values, [
    "post-a",
    "post-b",
    "post-c",
    "post-z",
  ]);
});

test("missing account stops before reading or locking feed state", async () => {
  let feedReadCount = 0;
  const db = {
    feedComment: { async findMany() { feedReadCount++; return []; } },
    feedLike: { async findMany() { feedReadCount++; return []; } },
    feedCommentLike: { async findMany() { feedReadCount++; return []; } },
    async $queryRaw() { return []; },
    async $executeRaw() { return 0; },
  };

  const impact = await prepareFeedStateForAccountDeletion({
    db: db as never,
    userId: "missing",
  });

  assert.deepEqual(impact, {
    commentPostIds: [],
    likedPostIds: [],
    likedCommentIds: [],
  });
  assert.equal(feedReadCount, 0);
});

test("account deletion reconciles comment and like counters after cascade", async () => {
  const reconcileQueries: CapturedSql[] = [];
  const db = {
    feedComment: { async findMany() { return []; } },
    feedLike: { async findMany() { return []; } },
    feedCommentLike: { async findMany() { return []; } },
    async $queryRaw() { return []; },
    async $executeRaw(query: CapturedSql) {
      reconcileQueries.push(query);
      return 2;
    },
  };

  await reconcileFeedStateAfterAccountHardDelete({
    db: db as never,
    impact: {
      commentPostIds: ["post-a", "post-z"],
      likedPostIds: ["post-b"],
      likedCommentIds: ["comment-a", "comment-z"],
    },
  });

  assert.equal(reconcileQueries.length, 3);
  assert.match(reconcileQueries[0].sql, /SET "commentCount"/);
  assert.deepEqual(reconcileQueries[0].values, ["post-a", "post-z"]);
  assert.match(reconcileQueries[1].sql, /SET "likeCount"/);
  assert.match(reconcileQueries[1].sql, /FROM "FeedLike"/);
  assert.deepEqual(reconcileQueries[1].values, ["post-b"]);
  assert.match(reconcileQueries[2].sql, /UPDATE "FeedComment"/);
  assert.match(reconcileQueries[2].sql, /FROM "FeedCommentLike"/);
  assert.deepEqual(reconcileQueries[2].values, ["comment-a", "comment-z"]);
});
