import test from "node:test";
import assert from "node:assert/strict";
import {
  MAX_TAGGED_USERS_PER_POST,
  parseTaggedUsersInput,
  serializeTaggedUsers,
} from "../lib/feed/tagged-users";

test("limit 20 tag per post", () => {
  const raw = Array.from({ length: 21 }, (_, i) => ({
    userId: `u${i}`,
    mediaIndex: 0,
    x: 0.5,
    y: 0.5,
  }));
  const result = parseTaggedUsersInput(raw, { mediaCount: 3, isVideo: false });
  assert.equal(result.ok, false);
  assert.equal(MAX_TAGGED_USERS_PER_POST, 20);
});

test("koordinat harus 0-1", () => {
  const bad = parseTaggedUsersInput(
    [{ userId: "u1", mediaIndex: 0, x: 1.2, y: 0.5 }],
    { mediaCount: 1, isVideo: false },
  );
  assert.equal(bad.ok, false);
  const good = parseTaggedUsersInput(
    [{ userId: "u1", mediaIndex: 0, x: 0, y: 1 }],
    { mediaCount: 1, isVideo: false },
  );
  assert.equal(good.ok, true);
});

test("mediaIndex harus menunjuk foto yang ada", () => {
  const result = parseTaggedUsersInput(
    [{ userId: "u1", mediaIndex: 3, x: 0.5, y: 0.5 }],
    { mediaCount: 3, isVideo: false },
  );
  assert.equal(result.ok, false);
});

test("duplikat userId di-dedupe (yang pertama menang)", () => {
  const result = parseTaggedUsersInput(
    [
      { userId: "u1", mediaIndex: 0, x: 0.1, y: 0.1 },
      { userId: "u1", mediaIndex: 1, x: 0.9, y: 0.9 },
    ],
    { mediaCount: 2, isVideo: false },
  );
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.tags.length, 1);
    assert.equal(result.tags[0].mediaIndex, 0);
  }
});

test("video: mediaIndex/x/y dipaksa null", () => {
  const result = parseTaggedUsersInput(
    [{ userId: "u1" }, { userId: "u2", x: 0.5, y: 0.5, mediaIndex: 0 }],
    { mediaCount: 0, isVideo: true },
  );
  assert.equal(result.ok, true);
  if (result.ok) {
    for (const tag of result.tags) {
      assert.equal(tag.mediaIndex, null);
      assert.equal(tag.x, null);
      assert.equal(tag.y, null);
    }
  }
});

test("raw bukan array / kosong → ok dengan tags []", () => {
  assert.deepEqual(parseTaggedUsersInput(undefined, { mediaCount: 1, isVideo: false }), {
    ok: true,
    tags: [],
  });
  assert.deepEqual(parseTaggedUsersInput([], { mediaCount: 1, isVideo: false }), {
    ok: true,
    tags: [],
  });
});

test("serialize: admin di-brand-kan, mediaId → mediaIndex", () => {
  const rows = [
    {
      mediaId: "m2",
      x: 0.3,
      y: 0.7,
      hidden: false,
      taggedUser: {
        id: "admin1",
        username: "natalopetshop",
        name: "Natasha",
        role: "ADMIN",
        profilePhotoUrl: "https://cdn/x/natasha.jpg",
      },
    },
    {
      mediaId: "m1",
      x: 0.5,
      y: 0.5,
      hidden: false,
      taggedUser: {
        id: "cust1",
        username: "asiong",
        name: "Asiong",
        role: "CUSTOMER",
        profilePhotoUrl: "https://cdn/x/asiong.jpg",
      },
    },
  ];
  const out = serializeTaggedUsers(
    rows,
    new Map([
      ["m1", 0],
      ["m2", 1],
    ]),
  );
  assert.equal(out[0].name, "Natalo Petshop Official");
  assert.equal(out[0].profilePhotoUrl, null); // klien render logo brand
  assert.equal(out[0].mediaIndex, 1);
  assert.equal(out[1].name, "Asiong");
  assert.equal(out[1].mediaIndex, 0);
});

test("pesan error limit menyebut angka 20 (dipakai snackbar client)", () => {
  const raw = Array.from({ length: 21 }, (_, i) => ({
    userId: `u${i}`,
    mediaIndex: 0,
    x: 0.5,
    y: 0.5,
  }));
  const result = parseTaggedUsersInput(raw, { mediaCount: 1, isVideo: false });
  assert.equal(result.ok, false);
  if (!result.ok) assert.match(result.error, /20/);
});
