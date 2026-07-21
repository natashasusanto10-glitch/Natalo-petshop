import assert from "node:assert/strict";
import test from "node:test";
import { bunnyDisplayDimensions } from "@/lib/feed/bunny";

// ---------------------------------------------------------------------------
// Bunny reports the CODED width/height of the source plus a rotation flag.
// Portrait phone clips are frequently stored as landscape pixels (1920×1080)
// with rotation=90/270; persisting those verbatim frames the post as landscape
// → "postingan portrait jadi hitam kiri-kanan". bunnyDisplayDimensions swaps
// the pair on a quarter turn so the feed frame matches the rotated playback
// (and Instagram). Behaviour is locked here.
// ---------------------------------------------------------------------------

test("rotation 0 → dims unchanged (already display-oriented)", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1080, height: 1920, rotation: 0 }),
    { width: 1080, height: 1920 },
  );
});

test("landscape source unchanged when no rotation", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080, rotation: 0 }),
    { width: 1920, height: 1080 },
  );
});

test("rotation 90 swaps landscape coded dims → portrait display dims", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080, rotation: 90 }),
    { width: 1080, height: 1920 },
  );
});

test("rotation 270 also swaps (other quarter turn)", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080, rotation: 270 }),
    { width: 1080, height: 1920 },
  );
});

test("rotation 180 does NOT swap (upside-down keeps orientation)", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080, rotation: 180 }),
    { width: 1920, height: 1080 },
  );
});

test("negative rotation normalizes (-90 ≡ 270 → swap)", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080, rotation: -90 }),
    { width: 1080, height: 1920 },
  );
});

test("near-quarter rotation rounds to nearest turn (89.98 → 90 → swap)", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080, rotation: 89.98 }),
    { width: 1080, height: 1920 },
  );
});

test("missing rotation defaults to 0 (no swap)", () => {
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 1920, height: 1080 }),
    { width: 1920, height: 1080 },
  );
});

test("null / zero / non-finite dims pass through as null (callers keep ?? null)", () => {
  assert.deepEqual(bunnyDisplayDimensions(null), { width: null, height: null });
  assert.deepEqual(
    bunnyDisplayDimensions({ width: 0, height: 0, rotation: 90 }),
    { width: null, height: null },
  );
  assert.deepEqual(
    bunnyDisplayDimensions({ width: null, height: 1920, rotation: 90 }),
    { width: null, height: 1920 },
  );
});
