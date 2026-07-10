import { test } from "node:test";
import assert from "node:assert/strict";
import {
  productVideoPayload,
  resolveProductVideoWebhookUpdate,
} from "../lib/product/product-video-serialize";

test("productVideoPayload: sembunyikan URL saat belum ready", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: "processing",
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    }),
    { videoUrl: null, videoThumbnailUrl: null, videoDurationSec: null },
  );
});

test("productVideoPayload: null status → semua null", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: null,
      videoUrl: null,
      videoThumbnailUrl: null,
      videoDurationSec: null,
    }),
    { videoUrl: null, videoThumbnailUrl: null, videoDurationSec: null },
  );
});

test("productVideoPayload: ready → kirim URL", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: "ready",
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    }),
    {
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    },
  );
});

test("productVideoPayload: ready tapi videoUrl kosong → semua null (guard)", () => {
  assert.deepEqual(
    productVideoPayload({
      videoStatus: "ready",
      videoUrl: null,
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    }),
    { videoUrl: null, videoThumbnailUrl: null, videoDurationSec: null },
  );
});

test("webhook: status non-terminal → processing", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 3,
      currentStatus: "uploading",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    { kind: "processing" },
  );
});

test("webhook: sudah settled → ignore (retry)", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 4,
      currentStatus: "ready",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    { kind: "ignore" },
  );
});

test("webhook: ERROR → failed", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 5,
      currentStatus: "processing",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    { kind: "failed" },
  );
});

test("webhook: FINISHED → ready dengan URL", () => {
  assert.deepEqual(
    resolveProductVideoWebhookUpdate({
      status: 4,
      currentStatus: "processing",
      playlistUrl: "https://cdn/x/playlist.m3u8",
      thumbnailUrl: "https://cdn/x/thumbnail.jpg",
      durationSec: 20,
    }),
    {
      kind: "ready",
      videoUrl: "https://cdn/x/playlist.m3u8",
      videoThumbnailUrl: "https://cdn/x/thumbnail.jpg",
      videoDurationSec: 20,
    },
  );
});
