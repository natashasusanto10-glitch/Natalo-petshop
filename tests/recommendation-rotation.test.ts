import assert from "node:assert/strict";
import test from "node:test";
import {
  seededShuffle,
  orderScoredCandidates,
} from "@/lib/recommendation-rotation";

const items = (list: string[]) => list.map((id) => ({ id }));
const ids = (arr: { product: { id: string } }[]) => arr.map((s) => s.product.id);

test("seededShuffle: seed kosong -> urutan input (identitas, backward-compat)", () => {
  const input = items(["a", "b", "c", "d"]);
  assert.deepEqual(seededShuffle(input, "").map((x) => x.id), ["a", "b", "c", "d"]);
});

test("seededShuffle: deterministik untuk seed sama", () => {
  const input = items(["a", "b", "c", "d", "e"]);
  const one = seededShuffle(input, "seed-1").map((x) => x.id);
  const two = seededShuffle(input, "seed-1").map((x) => x.id);
  assert.deepEqual(one, two);
});

test("seededShuffle: seed beda -> urutan beda (rotasi antar-kunjungan)", () => {
  const input = items(["a", "b", "c", "d", "e", "f", "g", "h"]);
  const one = seededShuffle(input, "seed-1").map((x) => x.id).join(",");
  const two = seededShuffle(input, "seed-2").map((x) => x.id).join(",");
  assert.notEqual(one, two);
});

test("orderScoredCandidates: tanpa seed -> murni skor desc (backward-compat)", () => {
  const scored = [
    { product: { id: "low" }, score: 1 },
    { product: { id: "high" }, score: 9 },
    { product: { id: "mid" }, score: 5 },
  ];
  const out = ids(orderScoredCandidates(scored, { seed: "", isAnchor: () => false }));
  assert.deepEqual(out, ["high", "mid", "low"]);
});

test("orderScoredCandidates: anchor (repurchase) selalu di depan walau skor rendah", () => {
  const scored = [
    { product: { id: "filler" }, score: 9 },
    { product: { id: "refill" }, score: 1 },
  ];
  const out = ids(
    orderScoredCandidates(scored, { seed: "s", isAnchor: (p) => p.id === "refill" }),
  );
  assert.equal(out[0], "refill");
});

test("orderScoredCandidates: dengan seed, tier skor tinggi tetap sebelum tier rendah", () => {
  const scored = [
    { product: { id: "a" }, score: 0.2 },
    { product: { id: "b" }, score: 0.1 },
    { product: { id: "big" }, score: 8 },
  ];
  const out = ids(orderScoredCandidates(scored, { seed: "x", isAnchor: () => false }));
  assert.equal(out[0], "big");
});

test("orderScoredCandidates: dengan seed, deterministik untuk seed sama", () => {
  const scored = ["a", "b", "c", "d", "e"].map((id) => ({ product: { id }, score: 1 }));
  const one = ids(orderScoredCandidates(scored, { seed: "same", isAnchor: () => false }));
  const two = ids(orderScoredCandidates(scored, { seed: "same", isAnchor: () => false }));
  assert.deepEqual(one, two);
});

test("orderScoredCandidates: seed beda -> tier sama dirotasi beda", () => {
  const scored = ["a", "b", "c", "d", "e", "f"].map((id) => ({ product: { id }, score: 1 }));
  const one = ids(orderScoredCandidates(scored, { seed: "s1", isAnchor: () => false })).join(",");
  const two = ids(orderScoredCandidates(scored, { seed: "s2", isAnchor: () => false })).join(",");
  assert.notEqual(one, two);
});
