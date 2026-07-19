import { test } from "node:test";
import assert from "node:assert/strict";
import {
  notificationActorFields,
  likeRowActorFields,
  OFFICIAL_BRAND_NAME,
} from "../lib/social/brand-user";

test("admin actor → nama brand, avatar null (tak bocor foto/nama pemilik)", () => {
  const r = notificationActorFields("ADMIN", "Natasha", "https://cdn/natasha.jpg");
  assert.equal(r.actorName, OFFICIAL_BRAND_NAME);
  assert.equal(r.actorAvatarUrl, null);
});

test("user biasa → nama & foto asli", () => {
  const r = notificationActorFields("USER", "Andi", "https://cdn/andi.jpg");
  assert.equal(r.actorName, "Andi");
  assert.equal(r.actorAvatarUrl, "https://cdn/andi.jpg");
});

test("user tanpa foto/nama → null", () => {
  const r = notificationActorFields("USER", null, null);
  assert.equal(r.actorName, null);
  assert.equal(r.actorAvatarUrl, null);
});

test("nama kosong/whitespace → null (bukan string kosong)", () => {
  assert.equal(notificationActorFields("USER", "   ", null).actorName, null);
  assert.equal(notificationActorFields("USER", "", null).actorName, null);
  assert.equal(notificationActorFields("USER", "  Andi  ", null).actorName, "Andi");
});

test("likeRowActorFields: agregat → null (identitas aktor tunggal hilang)", () => {
  const single = { actorName: "Andi", actorAvatarUrl: "https://cdn/a.jpg" };
  assert.deepEqual(likeRowActorFields(false, single), single);
  assert.deepEqual(likeRowActorFields(true, single), {
    actorName: null,
    actorAvatarUrl: null,
  });
});
