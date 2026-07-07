import test from "node:test";
import assert from "node:assert/strict";
import { rankBadgeClass } from "../lib/rank-badge";

test("top 3 ranks get distinct colors", () => {
  assert.equal(rankBadgeClass(1), "bg-amber-400 text-white");
  assert.equal(rankBadgeClass(2), "bg-zinc-300 text-zinc-700");
  assert.equal(rankBadgeClass(3), "bg-blue-300 text-white");
});

test("rank 4+ uses neutral", () => {
  assert.equal(rankBadgeClass(4), "bg-white/95 text-zinc-700");
  assert.equal(rankBadgeClass(10), "bg-white/95 text-zinc-700");
});
