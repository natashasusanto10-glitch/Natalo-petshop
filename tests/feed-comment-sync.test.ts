import assert from "node:assert/strict";
import test from "node:test";
import {
  countedFeedCommentWhere,
  findChangedFeedCommentRootIds,
  findRemovedFeedCommentIds,
  readDatabaseSnapshotClock,
  resolveFeedCommentSyncWindow,
  visibleFeedCommentWhere,
  visibleFeedCommentRootWhere,
} from "@/lib/feed/comment-sync";
import { listFeedComments } from "@/lib/feed/queries";

const now = new Date("2026-07-15T12:00:00.000Z");

test("comment sync omits removal scans without a client watermark", () => {
  const window = resolveFeedCommentSyncWindow({ now });

  assert.deepEqual(window, {
    requested: false,
    since: null,
    resetRequired: false,
  });
});

test("comment sync uses the exact commit cursor without timestamp overlap", () => {
  const window = resolveFeedCommentSyncWindow({
    syncCursor: "2026-07-15T11:30:00.000Z",
    now,
  });

  assert.equal(window.requested, true);
  assert.equal(window.resetRequired, false);
  assert.equal(window.since?.toISOString(), "2026-07-15T11:30:00.000Z");
});

test("comment sync rejects malformed cursors without scanning a partial window", () => {
  const window = resolveFeedCommentSyncWindow({
    syncCursor: "not-a-date",
    now,
  });

  assert.deepEqual(window, {
    requested: true,
    since: null,
    resetRequired: true,
  });
});

test("an old unchanged post cursor remains valid indefinitely", () => {
  const oldCursor = "2020-01-01T00:00:00.000Z";
  const firstPoll = resolveFeedCommentSyncWindow({
    syncCursor: oldCursor,
    now,
  });
  const laterPoll = resolveFeedCommentSyncWindow({
    syncCursor: oldCursor,
    now: new Date("2027-07-15T12:00:00.000Z"),
  });

  for (const window of [firstPoll, laterPoll]) {
    assert.equal(window.requested, true);
    assert.equal(window.resetRequired, false);
    assert.equal(window.since?.toISOString(), oldCursor);
  }
});

test("comment sync rejects a cursor too far in the future", () => {
  const window = resolveFeedCommentSyncWindow({
    syncTime: "2026-07-15T12:02:00.000Z",
    now,
  });

  assert.equal(window.resetRequired, true);
  assert.equal(window.since, null);
});

test("comment sync resets a cursor ahead of the current post cursor", () => {
  const window = resolveFeedCommentSyncWindow({
    syncCursor: "2026-07-15T11:59:00.000Z",
    now,
    currentCursor: new Date("2026-07-15T11:58:00.000Z"),
  });

  assert.equal(window.resetRequired, true);
  assert.equal(window.since, null);
});

test("comment sync watermark comes from the transaction snapshot clock", async () => {
  let sql = "";
  const db = {
    async $queryRaw(strings: TemplateStringsArray) {
      sql = strings.join("?");
      return [{ now }];
    },
  };

  const result = await readDatabaseSnapshotClock(db as never);

  assert.equal(result, now);
  assert.match(sql, /transaction_timestamp\(\)/);
  assert.doesNotMatch(sql, /FOR SHARE/i);
});

test("removed parent tombstones explicitly include loaded reply IDs", async () => {
  const calls: unknown[] = [];
  const responses = [
    [
      { id: "parent-1", parentCommentId: null, syncVersion: now },
      {
        id: "reply-direct",
        parentCommentId: "parent-2",
        syncVersion: new Date(now.getTime() + 1),
      },
    ],
    [],
    [{ id: "reply-1" }, { id: "reply-2" }],
  ];
  const db = {
    feedComment: {
      async findMany(args: unknown) {
        calls.push(args);
        return responses.shift() ?? [];
      },
    },
    feedCommentTombstone: {
      async findMany() {
        return [];
      },
    },
  };

  const result = await findRemovedFeedCommentIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxIds: 10,
  });

  assert.deepEqual(result, {
    removedCommentIds: ["parent-1", "reply-direct", "reply-1", "reply-2"],
    resetRequired: false,
  });
  assert.equal(calls.length, 3);
});

test("deleting the last reply also tombstones its self-deleted parent", async () => {
  const responses = [
    [{ id: "reply-last", parentCommentId: "parent-deleted", syncVersion: now }],
    [{ id: "parent-deleted" }],
    [{ id: "reply-last" }],
  ];
  const db = {
    feedComment: {
      async findMany() {
        return responses.shift() ?? [];
      },
    },
    feedCommentTombstone: {
      async findMany() {
        return [];
      },
    },
  };

  const result = await findRemovedFeedCommentIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxIds: 10,
  });

  assert.deepEqual(result, {
    removedCommentIds: ["reply-last", "parent-deleted"],
    resetRequired: false,
  });
});

test("removed comment scans are capped and require reset on overflow", async () => {
  let requestedTake = 0;
  const db = {
    feedComment: {
      async findMany(args: { take: number }) {
        requestedTake = args.take;
        return [
          { id: "one", parentCommentId: null, syncVersion: now },
          {
            id: "two",
            parentCommentId: null,
            syncVersion: new Date(now.getTime() + 1),
          },
          {
            id: "three",
            parentCommentId: null,
            syncVersion: new Date(now.getTime() + 2),
          },
        ];
      },
    },
    feedCommentTombstone: {
      async findMany() {
        return [];
      },
    },
  };

  const result = await findRemovedFeedCommentIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxIds: 2,
  });

  assert.equal(requestedTake, 3);
  assert.deepEqual(result, {
    removedCommentIds: ["one", "two"],
    resetRequired: true,
  });
});

test("hard-delete tombstones are merged with soft removals", async () => {
  const db = {
    feedComment: {
      async findMany() {
        return [];
      },
    },
    feedCommentTombstone: {
      async findMany() {
        return [
          {
            commentId: "hard-parent",
            parentCommentId: null,
            syncVersion: new Date("2026-07-15T11:30:00.000Z"),
          },
          {
            commentId: "hard-reply",
            parentCommentId: "hard-parent",
            syncVersion: new Date("2026-07-15T11:30:00.001Z"),
          },
        ];
      },
      async count() {
        return 3;
      },
    },
  };

  const result = await findRemovedFeedCommentIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxIds: 10,
  });

  assert.deepEqual(result, {
    removedCommentIds: ["hard-parent", "hard-reply"],
    resetRequired: false,
  });
});

test("commit cursor returns stale-timestamp late commits and maps replies to their root", async () => {
  let changedWhere: unknown;
  const db = {
    feedComment: {
      async findMany(args: { where: unknown }) {
        changedWhere = args.where;
        return [
          { id: "old-root", parentCommentId: null },
          { id: "reply-1", parentCommentId: "old-root" },
          { id: "reply-2", parentCommentId: "another-root" },
        ];
      },
      async count() {
        return 3;
      },
    },
  };

  const result = await findChangedFeedCommentRootIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxChanges: 10,
  });

  assert.deepEqual(result, {
    rootCommentIds: ["old-root", "another-root"],
    resetRequired: false,
  });
  assert.deepEqual(changedWhere, {
    AND: [
      visibleFeedCommentWhere("post-1"),
      {
        syncVersion: {
          gt: new Date("2026-07-15T11:00:00.000Z"),
          lte: now,
        },
      },
    ],
  });
});

test("changed thread response budget counts roots and all serialized replies", async () => {
  let countWhere: unknown;
  const db = {
    feedComment: {
      async findMany() {
        return [{ id: "reply-1", parentCommentId: "large-root" }];
      },
      async count(args: { where: unknown }) {
        countWhere = args.where;
        return 11;
      },
    },
  };

  const result = await findChangedFeedCommentRootIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxChanges: 10,
  });

  assert.deepEqual(result, { rootCommentIds: [], resetRequired: true });
  assert.deepEqual(countWhere, {
    AND: [
      visibleFeedCommentWhere("post-1"),
      {
        OR: [
          { id: { in: ["large-root"] } },
          { parentCommentId: { in: ["large-root"] } },
        ],
      },
    ],
  });
});

test("visible change overflow requires a reset instead of returning a partial delta", async () => {
  let requestedTake = 0;
  const db = {
    feedComment: {
      async findMany(args: { take: number }) {
        requestedTake = args.take;
        return [
          { id: "one", parentCommentId: null },
          { id: "two", parentCommentId: null },
          { id: "three", parentCommentId: null },
        ];
      },
    },
  };

  const result = await findChangedFeedCommentRootIds({
    db: db as never,
    postId: "post-1",
    since: new Date("2026-07-15T11:00:00.000Z"),
    until: now,
    maxChanges: 2,
  });

  assert.equal(requestedTake, 3);
  assert.deepEqual(result, { rootCommentIds: [], resetRequired: true });
});

test("comment listing appends changed roots outside the first page without moving its cursor", async () => {
  const author = {
    id: "user-1",
    name: "User",
    username: "user",
    role: "CUSTOMER",
    profilePhotoUrl: null,
  };
  const makeComment = (id: string, offset: number) => ({
    id,
    postId: "post-1",
    parentCommentId: null,
    content: `Comment ${id}`,
    isAdminOfficial: false,
    isHidden: false,
    deletedAt: null,
    likeCount: 0,
    createdAt: new Date(now.getTime() - offset),
    author,
    replies: [],
  });
  const firstPage = Array.from({ length: 21 }, (_, index) =>
    makeComment(`new-${index + 1}`, index)
  );
  const changedOldRoot = makeComment("old-unhidden", 60_000);
  let commentQuery = 0;
  const db = {
    feedComment: {
      async findMany() {
        commentQuery += 1;
        return commentQuery === 1 ? firstPage : [changedOldRoot];
      },
    },
    feedCommentLike: {
      async findMany() {
        return [];
      },
    },
    user: {
      async findMany() {
        return [];
      },
    },
  };

  const result = await listFeedComments({
    postId: "post-1",
    additionalRootIds: ["old-unhidden"],
    db: db as never,
  });

  assert.equal(result.items.length, 21);
  assert.equal(result.items.at(-1)?.id, "old-unhidden");
  assert.equal(result.nextCursor, "new-20");
});

test("visible rows preserve replies under a self-deleted parent", () => {
  assert.deepEqual(visibleFeedCommentWhere("post-1"), {
    postId: "post-1",
    isHidden: false,
    OR: [
      {
        parentCommentId: null,
        OR: [
          { deletedAt: null },
          { replies: { some: { isHidden: false, deletedAt: null } } },
        ],
      },
      {
        parentCommentId: { not: null },
        deletedAt: null,
        parent: { isHidden: false },
      },
    ],
  });
});

test("authoritative count excludes placeholder but keeps its visible replies", () => {
  assert.deepEqual(countedFeedCommentWhere("post-1"), {
    postId: "post-1",
    isHidden: false,
    deletedAt: null,
    OR: [{ parentCommentId: null }, { parent: { isHidden: false } }],
  });
});

test("self-deleted parent is returned as a placeholder with replies", async () => {
  const author = {
    id: "user-1",
    name: "User",
    username: "user",
    role: "CUSTOMER",
    profilePhotoUrl: null,
  };
  const deletedParent = {
    id: "parent-1",
    postId: "post-1",
    parentCommentId: null,
    content: "sensitive original text",
    isAdminOfficial: false,
    isHidden: false,
    deletedAt: new Date("2026-07-15T11:30:00.000Z"),
    likeCount: 7,
    createdAt: new Date("2026-07-15T10:00:00.000Z"),
    author,
    replies: [
      {
        id: "reply-1",
        postId: "post-1",
        parentCommentId: "parent-1",
        content: "reply remains",
        isAdminOfficial: false,
        isHidden: false,
        deletedAt: null,
        likeCount: 2,
        createdAt: new Date("2026-07-15T10:01:00.000Z"),
        author,
      },
    ],
  };
  const seenWhere: unknown[] = [];
  const db = {
    feedComment: {
      async findMany(args: { where: unknown }) {
        seenWhere.push(args.where);
        return [deletedParent];
      },
    },
    feedCommentLike: {
      async findMany() {
        return [];
      },
    },
    user: {
      async findMany() {
        return [];
      },
    },
  };

  const result = await listFeedComments({
    postId: "post-1",
    db: db as never,
  });

  assert.deepEqual(seenWhere[0], visibleFeedCommentRootWhere("post-1"));
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0]?.isDeleted, true);
  assert.equal(result.items[0]?.content, "Komentar dihapus");
  assert.equal(result.items[0]?.likeCount, 0);
  assert.equal(result.items[0]?.replies?.[0]?.content, "reply remains");
});
