import { test } from "node:test";
import assert from "node:assert/strict";
import {
  notificationActorFields,
  likeRowActorFields,
  topLikerAvatars,
  resolveNotificationActor,
  notificationActorLabels,
  fillNotificationActorTokens,
  NOTIF_ACTOR_NAME_TOKEN,
  NOTIF_ACTOR_USERNAME_TOKEN,
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

test("resolveNotificationActor: pakai foto LIVE terkini, bukan snapshot basi", () => {
  const r = resolveNotificationActor({
    actorId: "u1",
    isAggregate: false,
    snapshot: { actorName: "matcha_latte", actorAvatarUrl: "https://cdn/OLD.jpg" },
    liveUser: { role: "USER", name: "matcha_latte", profilePhotoUrl: null },
  });
  // Foto sudah dihapus di record User → live null (menimpa snapshot lama).
  assert.equal(r.actorAvatarUrl, null);
  assert.equal(r.actorName, "matcha_latte");
});

test("resolveNotificationActor: foto ganti → ikut foto baru", () => {
  const r = resolveNotificationActor({
    actorId: "u1",
    isAggregate: false,
    snapshot: { actorName: "Andi", actorAvatarUrl: "https://cdn/old.jpg" },
    liveUser: { role: "USER", name: "Andi", profilePhotoUrl: "https://cdn/new.jpg" },
  });
  assert.equal(r.actorAvatarUrl, "https://cdn/new.jpg");
});

test("resolveNotificationActor: actorId null (notif lama) → fallback snapshot", () => {
  const snapshot = { actorName: "Andi", actorAvatarUrl: "https://cdn/snap.jpg" };
  const r = resolveNotificationActor({
    actorId: null,
    isAggregate: false,
    snapshot,
    liveUser: { role: "USER", name: "Andi", profilePhotoUrl: "https://cdn/new.jpg" },
  });
  assert.deepEqual(r, snapshot);
});

test("resolveNotificationActor: user tak ditemukan → fallback snapshot", () => {
  const snapshot = { actorName: "Andi", actorAvatarUrl: "https://cdn/snap.jpg" };
  const r = resolveNotificationActor({
    actorId: "u1",
    isAggregate: false,
    snapshot,
    liveUser: null,
  });
  assert.deepEqual(r, snapshot);
});

test("resolveNotificationActor: baris agregat → snapshot (tak isi 1 avatar)", () => {
  // Baris like agregat menyimpan actorId dari like tunggal awal, tapi
  // identitas aktor tunggal sudah null (avatar bertumpuk di actorAvatarUrls).
  const snapshot = { actorName: null, actorAvatarUrl: null };
  const r = resolveNotificationActor({
    actorId: "u1",
    isAggregate: true,
    snapshot,
    liveUser: { role: "USER", name: "Andi", profilePhotoUrl: "https://cdn/new.jpg" },
  });
  assert.deepEqual(r, snapshot);
});

test("resolveNotificationActor: aktor admin → brand-safe live (nama brand, foto null)", () => {
  const r = resolveNotificationActor({
    actorId: "admin1",
    isAggregate: false,
    snapshot: { actorName: OFFICIAL_BRAND_NAME, actorAvatarUrl: null },
    liveUser: { role: "ADMIN", name: "Natasha", profilePhotoUrl: "https://cdn/natasha.jpg" },
  });
  assert.equal(r.actorName, OFFICIAL_BRAND_NAME);
  assert.equal(r.actorAvatarUrl, null);
});

test("notificationActorLabels: user biasa → nama & username asli", () => {
  const r = notificationActorLabels({ role: "USER", name: "Andi Wijaya", username: "andi_w" });
  assert.equal(r.nameLabel, "Andi Wijaya");
  assert.equal(r.usernameLabel, "andi_w");
});

test("notificationActorLabels: username kosong → jatuh ke nama", () => {
  const r = notificationActorLabels({ role: "USER", name: "Andi", username: null });
  assert.equal(r.usernameLabel, "Andi");
});

test("notificationActorLabels: semua kosong / user null → 'Seseorang'", () => {
  assert.deepEqual(notificationActorLabels({ role: "USER", name: null, username: null }), {
    nameLabel: "Seseorang",
    usernameLabel: "Seseorang",
  });
  assert.deepEqual(notificationActorLabels(null), {
    nameLabel: "Seseorang",
    usernameLabel: "Seseorang",
  });
});

test("notificationActorLabels: admin → nama brand (dua-duanya, tak bocor)", () => {
  const r = notificationActorLabels({ role: "ADMIN", name: "Natasha", username: "natasha_owner" });
  assert.equal(r.nameLabel, OFFICIAL_BRAND_NAME);
  assert.equal(r.usernameLabel, OFFICIAL_BRAND_NAME);
});

test("fillNotificationActorTokens: token judul diganti nama/username live", () => {
  const title = `${NOTIF_ACTOR_USERNAME_TOKEN} menyebut kamu di komentar`;
  const body = `${NOTIF_ACTOR_NAME_TOKEN} berkomentar`;
  assert.equal(
    fillNotificationActorTokens(title, { nameLabel: "Andi", usernameLabel: "andi_w" }),
    "andi_w menyebut kamu di komentar",
  );
  assert.equal(
    fillNotificationActorTokens(body, { nameLabel: "Andi", usernameLabel: "andi_w" }),
    "Andi berkomentar",
  );
});

test("fillNotificationActorTokens: teks tanpa token (notif lama) → apa adanya", () => {
  const old = "matcha_latte membalas komentarmu";
  assert.equal(
    fillNotificationActorTokens(old, { nameLabel: "X", usernameLabel: "y" }),
    old,
  );
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
