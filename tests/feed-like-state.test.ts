import assert from "node:assert/strict";
import test from "node:test";
import {
  isFeedCommentLikeable,
  lockFeedInteractionActor,
  reconcileFeedLikeState,
} from "@/lib/feed/like-state";

function createLikeStore(initialLikes: string[] = []) {
  const likes = new Set(initialLikes);
  let counter = -1;
  let creates = 0;
  let deletes = 0;
  const store = {
    async hasLike() {
      return likes.has("viewer");
    },
    async createLike() {
      creates += 1;
      likes.add("viewer");
    },
    async deleteLike() {
      deletes += 1;
      likes.delete("viewer");
    },
    async countLikes() {
      return likes.size;
    },
    async writeLikeCount(value: number) {
      counter = value;
    },
  };
  return {
    store,
    get counter() {
      return counter;
    },
    get creates() {
      return creates;
    },
    get deletes() {
      return deletes;
    },
  };
}

test("desired liked state is idempotent across retries", async () => {
  const state = createLikeStore(["other"]);

  const first = await reconcileFeedLikeState(state.store, true);
  const retry = await reconcileFeedLikeState(state.store, true);

  assert.deepEqual(first, { liked: true, likeCount: 2, changed: true });
  assert.deepEqual(retry, { liked: true, likeCount: 2, changed: false });
  assert.equal(state.creates, 1);
  assert.equal(state.counter, 2);
});

test("desired unliked state is idempotent across retries", async () => {
  const state = createLikeStore(["viewer", "other"]);

  const first = await reconcileFeedLikeState(state.store, false);
  const retry = await reconcileFeedLikeState(state.store, false);

  assert.deepEqual(first, { liked: false, likeCount: 1, changed: true });
  assert.deepEqual(retry, { liked: false, likeCount: 1, changed: false });
  assert.equal(state.deletes, 1);
  assert.equal(state.counter, 1);
});

test("legacy toggle still flips once per serialized request", async () => {
  const state = createLikeStore();

  const liked = await reconcileFeedLikeState(state.store, "toggle");
  const unliked = await reconcileFeedLikeState(state.store, "toggle");

  assert.equal(liked.liked, true);
  assert.equal(unliked.liked, false);
  assert.equal(state.creates, 1);
  assert.equal(state.deletes, 1);
});

test("canonical counter writes are floored at zero", async () => {
  let written = -1;
  const result = await reconcileFeedLikeState(
    {
      async hasLike() {
        return false;
      },
      async createLike() {},
      async deleteLike() {},
      async countLikes() {
        return -5;
      },
      async writeLikeCount(count) {
        written = count;
      },
    },
    false
  );

  assert.equal(result.likeCount, 0);
  assert.equal(written, 0);
});

test("unchanged idempotent intent skips an already-canonical counter write", async () => {
  let writes = 0;
  const result = await reconcileFeedLikeState(
    {
      async hasLike() {
        return true;
      },
      async createLike() {},
      async deleteLike() {},
      async countLikes() {
        return 3;
      },
      async readLikeCount() {
        return 3;
      },
      async writeLikeCount() {
        writes += 1;
      },
    },
    true
  );

  assert.equal(result.changed, false);
  assert.equal(writes, 0);
});

test("engagement actor lock uses User before target locks", async () => {
  let sql = "";
  let values: unknown[] = [];
  const db = {
    async $queryRaw(strings: TemplateStringsArray, ...params: unknown[]) {
      sql = strings.join("?");
      values = params;
      return [{ id: "viewer" }];
    },
  };

  const available = await lockFeedInteractionActor(db as never, "viewer");

  assert.equal(available, true);
  assert.match(sql, /FROM "User"/);
  assert.match(sql, /FOR KEY SHARE/);
  assert.deepEqual(values, ["viewer"]);
});

test("comment likes reject removed rows but allow replies under a deleted placeholder", () => {
  const live = { isHidden: false, deletedAt: null };
  const deletedAt = new Date("2026-07-15T12:00:00.000Z");

  assert.equal(isFeedCommentLikeable(live), true);
  assert.equal(isFeedCommentLikeable({ ...live, isHidden: true }), false);
  assert.equal(isFeedCommentLikeable({ ...live, deletedAt }), false);
  assert.equal(
    isFeedCommentLikeable({
      ...live,
      parent: { isHidden: true, deletedAt: null },
    }),
    false
  );
  assert.equal(
    isFeedCommentLikeable({
      ...live,
      parent: { isHidden: false, deletedAt },
    }),
    true
  );
});
