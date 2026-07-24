import test from "node:test";
import assert from "node:assert/strict";
import { sendFollowNotification } from "../lib/social/notifications";
import { AGG_PUSH_THROTTLE_MS } from "../lib/social/follow-aggregation";

const T0 = new Date("2026-07-24T10:00:00Z");

function makeFollower(over: Partial<Record<string, unknown>> = {}) {
  return {
    id: "f1",
    name: "Sinta",
    username: "sinta",
    role: "CUSTOMER",
    profilePhotoUrl: "https://cdn/sinta.jpg",
    ...over,
  };
}

/** Fake prisma minimal utk jalur follow. Atur skenario via fields. */
function makeDb(scenario: {
  follower?: ReturnType<typeof makeFollower> | null;
  dedupHit?: boolean;
  aggRow?: {
    id: string;
    createdAt: Date;
    lastPushedAt: Date | null;
  } | null;
  followCountSince?: number;
  recentFollowers?: Array<{
    follower: { role: string; profilePhotoUrl: string | null };
  }>;
}) {
  const calls: {
    updates: Array<{ where: unknown; data: Record<string, unknown> }>;
    creates: Array<{ data: Record<string, unknown> }>;
    countArgs: unknown[];
  } = { updates: [], creates: [], countArgs: [] };
  const db = {
    user: {
      findUnique: async () => scenario.follower ?? makeFollower(),
    },
    announcement: {
      findFirst: async (args: { where: Record<string, unknown> }) => {
        // Panggilan dedup punya `url` di where; pencarian agregat tidak.
        if ("url" in args.where) {
          return scenario.dedupHit ? { id: "dedup" } : null;
        }
        return scenario.aggRow ?? null;
      },
      update: async (args: { where: unknown; data: Record<string, unknown> }) => {
        calls.updates.push(args);
        return {};
      },
      create: async (args: { data: Record<string, unknown> }) => {
        calls.creates.push(args);
        return {};
      },
    },
    userFollow: {
      count: async (args: unknown) => {
        calls.countArgs.push(args);
        return scenario.followCountSince ?? 0;
      },
      findMany: async () => scenario.recentFollowers ?? [],
    },
  };
  return { db: db as never, calls };
}

test("follow pertama (tanpa baris hidup) → create tunggal, aggregatedCount null, url profil", async () => {
  const { db, calls } = makeDb({ aggRow: null });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async (_u, p) => void pushes.push(p),
      fcm: async () => {},
      now: () => T0,
    },
  );
  assert.equal(calls.creates.length, 1);
  const row = calls.creates[0].data;
  assert.equal(row.title, "Pengikut baru");
  assert.equal(row.url, "/u/sinta");
  assert.equal(row.aggregatedCount, null);
  assert.equal(row.actorId, "f1");
  assert.deepEqual(row.lastPushedAt, T0);
  assert.equal(pushes.length, 1);
});

test("follow kedua dalam window → update agregat: judul, count, avatar, aktor null, url followers", async () => {
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: T0 },
    followCountSince: 1,
    recentFollowers: [
      { follower: { role: "CUSTOMER", profilePhotoUrl: "https://cdn/sinta.jpg" } },
      { follower: { role: "CUSTOMER", profilePhotoUrl: "https://cdn/budi.jpg" } },
    ],
  });
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async () => {},
      fcm: async () => {},
      now: () => new Date(T0.getTime() + 2 * 60 * 1000),
    },
  );
  assert.equal(calls.updates.length, 1);
  const data = calls.updates[0].data;
  assert.equal(data.title, "sinta dan 1 lainnya mulai mengikuti kamu");
  assert.equal(data.aggregatedCount, 2);
  assert.equal(data.url, "/akun/followers");
  assert.equal(data.actorName, null);
  assert.equal(data.actorAvatarUrl, null);
  assert.equal(data.actorId, null);
  assert.deepEqual(data.actorAvatarUrls, [
    "https://cdn/sinta.jpg",
    "https://cdn/budi.jpg",
  ]);
  // Count anchored ke createdAt baris (Keputusan 10):
  const countArg = calls.countArgs[0] as {
    where: { createdAt: { gte: Date } };
  };
  assert.deepEqual(countArg.where.createdAt.gte, T0);
});

test("update <5m sejak lastPushedAt → TIDAK re-push, tapi baris tetap ter-update", async () => {
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: T0 },
    followCountSince: 1,
    recentFollowers: [],
  });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async (_u, p) => void pushes.push(p),
      fcm: async () => {},
      now: () => new Date(T0.getTime() + AGG_PUSH_THROTTLE_MS - 1000),
    },
  );
  assert.equal(pushes.length, 0);
  assert.equal(calls.updates.length, 1);
  assert.equal(calls.updates[0].data.lastPushedAt, undefined);
});

test("update >=5m → re-push dgn tag agregat + lastPushedAt maju", async () => {
  const later = new Date(T0.getTime() + AGG_PUSH_THROTTLE_MS);
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: T0 },
    followCountSince: 2,
    recentFollowers: [],
  });
  const pushes: Array<{ tag?: string; data?: Record<string, string> }> = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async (_u, p) => void pushes.push(p as never),
      fcm: async () => {},
      now: () => later,
    },
  );
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].tag, "follow-agg-t1");
  assert.equal(pushes[0].data?.aggregated_count, "3");
  assert.deepEqual(calls.updates[0].data.lastPushedAt, later);
});

test("dedup 7-hari tetap jalan: refollow follower baris tunggal → skip total", async () => {
  const { db, calls } = makeDb({ dedupHit: true });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    { db, push: async (_u, p) => void pushes.push(p), fcm: async () => {}, now: () => T0 },
  );
  assert.equal(calls.creates.length, 0);
  assert.equal(calls.updates.length, 0);
  assert.equal(pushes.length, 0);
});

test("follower admin di agregat → avatar TIDAK bocor (drop dari array)", async () => {
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: null },
    followCountSince: 1,
    recentFollowers: [
      { follower: { role: "ADMIN", profilePhotoUrl: "https://cdn/owner.jpg" } },
      { follower: { role: "CUSTOMER", profilePhotoUrl: "https://cdn/budi.jpg" } },
    ],
  });
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    { db, push: async () => {}, fcm: async () => {}, now: () => T0 },
  );
  assert.deepEqual(calls.updates[0].data.actorAvatarUrls, [
    "https://cdn/budi.jpg",
  ]);
});

test("lastPushedAt null (baris pra-migration) → boleh push", async () => {
  const { db } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: null },
    followCountSince: 1,
    recentFollowers: [],
  });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    { db, push: async (_u, p) => void pushes.push(p), fcm: async () => {}, now: () => T0 },
  );
  assert.equal(pushes.length, 1);
});
