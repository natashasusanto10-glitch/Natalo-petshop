import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { notifyTaggedUsersOnVideoReady } from "../lib/feed/activity-notifications";

/**
 * Final review Spec B fix: video tagged-user notification harus dipicu di
 * encodingStatus→ready transition (reconcile.ts / bunny webhook), BUKAN di
 * provision time (upload-url/route.ts). Lihat lib/feed/activity-notifications.ts
 * notifyTaggedUsersOnVideoReady untuk detail lengkap.
 */

function makeDb(rows: Array<{ taggedUserId: string }>) {
  return {
    feedTaggedUser: {
      async findMany() {
        return rows;
      },
    },
  } as never;
}

test("ready-transition: tidak notify siapa pun kalau tidak ada FeedTaggedUser tersimpan", async () => {
  let called = false;
  await notifyTaggedUsersOnVideoReady(
    { postId: "p1", actorUserId: "author1" },
    {
      db: makeDb([]),
      notify: async () => {
        called = true;
      },
    },
  );
  assert.equal(called, false);
});

test("ready-transition: notify SEMUA tagged user yang DI-RE-DERIVE dari DB (bukan data provision-time)", async () => {
  const calls: unknown[] = [];
  await notifyTaggedUsersOnVideoReady(
    { postId: "p1", actorUserId: "author1" },
    {
      // "DB" di sini sengaja beda dari asumsi provisioning manapun — bukti
      // bahwa daftar recipient BENAR-BENAR dibaca ulang dari lapisan DB
      // saat ready, bukan dibawa dari request upload-url yang sudah basi.
      db: makeDb([{ taggedUserId: "u1" }, { taggedUserId: "u2" }]),
      notify: async (args) => {
        calls.push(args);
      },
    },
  );
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], {
    actorUserId: "author1",
    recipientUserIds: ["u1", "u2"],
    postId: "p1",
  });
});

test("ready-transition: dedupe taggedUserId duplikat dari DB sebelum dispatch", async () => {
  const calls: Array<{ recipientUserIds: string[] }> = [];
  await notifyTaggedUsersOnVideoReady(
    { postId: "p1", actorUserId: "author1" },
    {
      db: makeDb([{ taggedUserId: "u1" }, { taggedUserId: "u1" }]),
      notify: async (args) => {
        calls.push(args as { recipientUserIds: string[] });
      },
    },
  );
  assert.deepEqual(calls[0].recipientUserIds, ["u1"]);
});

test("ready-transition: error saat baca DB ditelan (tidak throw), notify tidak dipanggil", async () => {
  let notifyCalled = false;
  await assert.doesNotReject(
    notifyTaggedUsersOnVideoReady(
      { postId: "p1", actorUserId: "author1" },
      {
        db: {
          feedTaggedUser: {
            async findMany() {
              throw new Error("db down");
            },
          },
        } as never,
        notify: async () => {
          notifyCalled = true;
        },
      },
    ),
  );
  assert.equal(notifyCalled, false);
});

// ── Regresi struktural: provisioning TIDAK LAGI memicu notif tagged-user ──

test("upload-url/route.ts (provision time) TIDAK LAGI memanggil sendTaggedUserNotifications", () => {
  const routeSource = readFileSync(
    resolve(process.cwd(), "app/api/feed/bunny/upload-url/route.ts"),
    "utf8",
  );
  assert.doesNotMatch(routeSource, /sendTaggedUserNotifications/);
});

test("reconcile.ts (ready-transition) memanggil notifyTaggedUsersOnVideoReady", () => {
  const source = readFileSync(
    resolve(process.cwd(), "lib/feed/reconcile.ts"),
    "utf8",
  );
  assert.match(source, /notifyTaggedUsersOnVideoReady/);
  // Panggilan harus di dalam blok FINISHED (encodingStatus: "ready"), bukan
  // sembarang tempat — sanity check urutan source: update encodingStatus
  // "ready" muncul SEBELUM pemanggilan notifyTaggedUsersOnVideoReady.
  const readyIdx = source.indexOf('encodingStatus: "ready"');
  const notifyIdx = source.indexOf("notifyTaggedUsersOnVideoReady");
  assert.ok(readyIdx >= 0 && notifyIdx >= 0 && readyIdx < notifyIdx);
});

test("bunny/webhook/route.ts (ready-transition) memanggil notifyTaggedUsersOnVideoReady", () => {
  const source = readFileSync(
    resolve(process.cwd(), "app/api/feed/bunny/webhook/route.ts"),
    "utf8",
  );
  assert.match(source, /notifyTaggedUsersOnVideoReady/);
  const readyIdx = source.indexOf('encodingStatus: "ready"');
  const notifyIdx = source.indexOf("notifyTaggedUsersOnVideoReady");
  assert.ok(readyIdx >= 0 && notifyIdx >= 0 && readyIdx < notifyIdx);
});
