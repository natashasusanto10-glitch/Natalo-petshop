import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MAX_FEED_ALT_TEXT_LENGTH,
  feedAccessibilityPayload,
  parseFeedAccessibilityMetadata,
  parseFeedAltText,
} from "../lib/feed/accessibility";

test("create metadata defaults omitted fields to null", () => {
  assert.deepEqual(parseFeedAccessibilityMetadata({}), {
    ok: true,
    data: {
      videoAltText: null,
      hasAudio: null,
      subtitleUrl: null,
      subtitleLanguage: null,
    },
  });
});

test("partial metadata preserves omitted fields and normalizes text", () => {
  assert.deepEqual(
    parseFeedAccessibilityMetadata(
      {
        videoAltText: "  Kucing bermain dengan bola.  ",
        hasAudio: false,
        subtitleUrl: " https://cdn.example.com/captions/post-1.vtt ",
        subtitleLanguage: " id-ID ",
      },
      { partial: true },
    ),
    {
      ok: true,
      data: {
        videoAltText: "Kucing bermain dengan bola.",
        hasAudio: false,
        subtitleUrl: "https://cdn.example.com/captions/post-1.vtt",
        subtitleLanguage: "id-ID",
      },
    },
  );
  assert.deepEqual(parseFeedAccessibilityMetadata({}, { partial: true }), {
    ok: true,
    data: {},
  });
});

test("alt text is bounded and blank values become null", () => {
  assert.deepEqual(parseFeedAltText("   "), { ok: true, data: null });
  const tooLong = parseFeedAltText("a".repeat(MAX_FEED_ALT_TEXT_LENGTH + 1));
  assert.equal(tooLong.ok, false);
});

test("subtitle URL must be absolute HTTPS without embedded credentials", () => {
  for (const subtitleUrl of [
    "http://cdn.example.com/post.vtt",
    "/captions/post.vtt",
    "javascript:alert(1)",
    "https://user:secret@cdn.example.com/post.vtt",
  ]) {
    const result = parseFeedAccessibilityMetadata(
      { subtitleUrl },
      { partial: true },
    );
    assert.equal(result.ok, false, subtitleUrl);
  }
});

test("subtitle language accepts short BCP47-like tags", () => {
  for (const subtitleLanguage of ["id", "en-US", "zh-Hant-TW"]) {
    assert.equal(
      parseFeedAccessibilityMetadata(
        { subtitleLanguage },
        { partial: true },
      ).ok,
      true,
      subtitleLanguage,
    );
  }
  for (const subtitleLanguage of ["i", "en_US", "en US", "toolonglanguage"]) {
    assert.equal(
      parseFeedAccessibilityMetadata(
        { subtitleLanguage },
        { partial: true },
      ).ok,
      false,
      subtitleLanguage,
    );
  }
});

test("hasAudio rejects non-boolean values", () => {
  assert.equal(
    parseFeedAccessibilityMetadata(
      { hasAudio: "true" },
      { partial: true },
    ).ok,
    false,
  );
});

test("serializer includes nullable metadata and transforms subtitle URL", () => {
  assert.deepEqual(
    feedAccessibilityPayload(
      {
        videoAltText: "Seekor anjing berlari.",
        hasAudio: true,
        subtitleUrl: "https://cdn.example.com/post.vtt",
        subtitleLanguage: "id",
      },
      (url) => `${url}?signed=1`,
    ),
    {
      videoAltText: "Seekor anjing berlari.",
      hasAudio: true,
      subtitleUrl: "https://cdn.example.com/post.vtt?signed=1",
      subtitleLanguage: "id",
    },
  );
});
