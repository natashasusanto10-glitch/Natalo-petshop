import { test } from "node:test";
import assert from "node:assert/strict";
import { productVideoMp4 } from "../lib/product/product-video-url";

test("null/undefined/empty → null", () => {
  assert.equal(productVideoMp4(null), null);
  assert.equal(productVideoMp4(undefined), null);
  assert.equal(productVideoMp4(""), null);
});

test("playlist → mp4 default 720p", () => {
  assert.equal(
    productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/playlist.m3u8"),
    "https://vz-abc.b-cdn.net/1a2b-3c/play_720p.mp4",
  );
});

test("height 360", () => {
  assert.equal(
    productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/playlist.m3u8", 360),
    "https://vz-abc.b-cdn.net/1a2b-3c/play_360p.mp4",
  );
});

test("preserves query string", () => {
  assert.equal(
    productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/playlist.m3u8?token=x&expires=1", 240),
    "https://vz-abc.b-cdn.net/1a2b-3c/play_240p.mp4?token=x&expires=1",
  );
});

test("non-playlist / non-bunny URL → null", () => {
  assert.equal(productVideoMp4("https://example.com/video.mp4"), null);
  assert.equal(productVideoMp4("https://vz-abc.b-cdn.net/1a2b-3c/thumbnail.jpg"), null);
});
