import assert from "node:assert/strict";
import test from "node:test";
import { checkFeedCommentRateLimit } from "@/lib/feed/comment-rate-limit";

const now = new Date("2026-07-15T12:00:00.000Z");

test("comment rate limit acquires the author lock before reading the window count", async () => {
  const events: string[] = [];
  let countWhere: unknown;
  const db = {
    async $queryRaw(strings: TemplateStringsArray) {
      const sql = strings.join("?");
      if (sql.includes("pg_advisory_xact_lock")) {
        events.push("lock");
        return [{ locked: 1 }];
      }
      events.push("clock");
      return [{ now }];
    },
    feedComment: {
      async count(args: { where: unknown }) {
        events.push("count");
        countWhere = args.where;
        return 10;
      },
    },
  };

  const result = await checkFeedCommentRateLimit({
    db: db as never,
    userId: "user-1",
    limit: 10,
    windowMs: 300_000,
  });

  assert.deepEqual(events, ["lock", "clock", "count"]);
  assert.deepEqual(countWhere, {
    authorId: "user-1",
    createdAt: { gte: new Date("2026-07-15T11:55:00.000Z") },
  });
  assert.deepEqual(result, {
    limited: true,
    recentCount: 10,
    retryAfterMs: 300_000,
  });
});

test("comment rate limit allows the request immediately below the bound", async () => {
  const db = {
    async $queryRaw(strings: TemplateStringsArray) {
      return strings.join("?").includes("clock_timestamp")
        ? [{ now }]
        : [{ locked: 1 }];
    },
    feedComment: {
      async count() {
        return 9;
      },
    },
  };

  const result = await checkFeedCommentRateLimit({
    db: db as never,
    userId: "user-1",
    limit: 10,
  });

  assert.equal(result.limited, false);
  assert.equal(result.recentCount, 9);
});
