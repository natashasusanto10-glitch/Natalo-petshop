import assert from "node:assert/strict";
import test from "node:test";

import {
  isSearchKeywordAllowed,
  normalizeSearchKeyword,
  rankTrendingKeywords,
  toSearchDisplayLabel,
} from "../lib/search-trending";

test("normalizes equivalent search queries", () => {
  assert.equal(normalizeSearchKeyword("  Royal   CANIN  \n"), "royal canin");
  assert.equal(normalizeSearchKeyword("Ｐａｓｉｒ Kucing"), "pasir kucing");
});

test("rejects unsafe or meaningless search terms", () => {
  assert.equal(isSearchKeywordAllowed("https://example.com"), false);
  assert.equal(isSearchKeywordAllowed("!!!"), false);
  assert.equal(isSearchKeywordAllowed("bokep-gratis"), false);
  assert.equal(isSearchKeywordAllowed("makanan babi"), true);
  assert.equal(isSearchKeywordAllowed("makanan kucing"), true);
});

test("ranks recent growth above a stagnant query", () => {
  const result = rankTrendingKeywords({
    current7d: [
      { keyword: "royal canin", count: 10 },
      { keyword: "pasir kucing", count: 8 },
      { keyword: "sekali saja", count: 1 },
    ],
    previous7d: [
      { keyword: "royal canin", count: 10 },
      { keyword: "pasir kucing", count: 1 },
    ],
    recent24h: [
      { keyword: "royal canin", count: 1 },
      { keyword: "pasir kucing", count: 5 },
    ],
  });

  assert.deepEqual(
    result.map((item) => item.keyword),
    ["pasir kucing", "royal canin"]
  );
  assert.equal(
    result.some((item) => item.keyword === "sekali saja"),
    false
  );
});

test("formats API labels for display", () => {
  assert.equal(toSearchDisplayLabel("royal canin"), "Royal Canin");
  assert.equal(toSearchDisplayLabel("cat's best"), "Cat's Best");
});
