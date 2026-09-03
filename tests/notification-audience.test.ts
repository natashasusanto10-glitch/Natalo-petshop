import { test } from "node:test";
import assert from "node:assert/strict";

import { announcementAudienceWhere } from "../lib/notification-audience";

const REGISTERED = new Date("2026-09-01T10:00:00Z");

test("broadcast dibatasi sejak akun lahir — akun baru mulai dari daftar kosong", () => {
  const where = announcementAudienceWhere({
    userId: "u1",
    allowedSegments: ["all"],
    viewerCreatedAt: REGISTERED,
  });
  const broadcast = where.OR[0] as Record<string, unknown>;
  assert.deepEqual(broadcast.createdAt, { gte: REGISTERED });
});

test("notifikasi PERSONAL tidak ikut dibatasi tanggal", () => {
  // Status pesanan / poin memang tercipta untuk akun ini; membatasinya bisa
  // menyembunyikan notifikasi sah (mis. clock skew antara created user dan
  // notifikasi pertama yang lahir di transaksi yang sama).
  const where = announcementAudienceWhere({
    userId: "u1",
    allowedSegments: ["all"],
    viewerCreatedAt: REGISTERED,
  });
  const personal = where.OR[1] as Record<string, unknown>;
  assert.deepEqual(personal, { targetUserId: "u1" });
});

test("viewer tak ditemukan → tanpa filter tanggal, bukan menyembunyikan semuanya", () => {
  const where = announcementAudienceWhere({
    userId: "u1",
    allowedSegments: ["all", "members"],
    viewerCreatedAt: null,
  });
  const broadcast = where.OR[0] as Record<string, unknown>;
  assert.equal("createdAt" in broadcast, false);
  assert.deepEqual(broadcast.segment, { in: ["all", "members"] });
});

test("segmen yang diizinkan diteruskan apa adanya", () => {
  const where = announcementAudienceWhere({
    userId: "u9",
    allowedSegments: ["all", "members", "active30d"],
    viewerCreatedAt: REGISTERED,
  });
  const broadcast = where.OR[0] as Record<string, unknown>;
  assert.deepEqual(broadcast.segment, { in: ["all", "members", "active30d"] });
  assert.equal(broadcast.targetUserId, null);
});
