import { test } from "node:test";
import assert from "node:assert/strict";
import {
  notificationActorFields,
  likeRowActorFields,
  topLikerAvatars,
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

test("topLikerAvatars: foto non-admin, admin di-drop, maks 3", () => {
  const r = topLikerAvatars([
    { role: "USER", profilePhotoUrl: "https://cdn/1.jpg" },
    { role: "ADMIN", profilePhotoUrl: "https://cdn/owner.jpg" }, // admin → drop
    { role: "USER", profilePhotoUrl: "https://cdn/2.jpg" },
    { role: "USER", profilePhotoUrl: "https://cdn/3.jpg" },
    { role: "USER", profilePhotoUrl: "https://cdn/4.jpg" }, // > 3 → dibuang
  ]);
  assert.deepEqual(r, ["https://cdn/1.jpg", "https://cdn/2.jpg", "https://cdn/3.jpg"]);
});

test("topLikerAvatars: null/empty foto dibuang", () => {
  assert.deepEqual(
    topLikerAvatars([
      { role: "USER", profilePhotoUrl: null },
      { role: "USER", profilePhotoUrl: "  " },
      { role: "USER", profilePhotoUrl: "https://cdn/x.jpg" },
    ]),
    ["https://cdn/x.jpg"],
  );
});
