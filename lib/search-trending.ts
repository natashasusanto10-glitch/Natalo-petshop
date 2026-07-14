export type SearchCount = {
  keyword: string;
  count: number;
};

export type TrendingKeyword = {
  keyword: string;
  count7d: number;
  count24h: number;
  previousCount7d: number;
  growth: number;
  score: number;
};

const DEFAULT_BLOCKED_TERMS = [
  "anjing lu",
  "bangsat",
  "bokep",
  "kontol",
  "memek",
  "ngentot",
  "porn",
  "porno",
  "sex",
  "seks",
];

export function normalizeSearchKeyword(value: unknown): string {
  return String(value ?? "")
    .normalize("NFKC")
    .toLocaleLowerCase("id-ID")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
}

export function isSearchKeywordAllowed(
  keyword: string,
  extraBlockedTerms = process.env.SEARCH_BLOCKED_TERMS ?? ""
): boolean {
  if (keyword.length < 2) return false;
  if (/https?:\/\/|www\.|\S+@\S+\.\S+/.test(keyword)) return false;
  if (!/[\p{L}\p{N}]/u.test(keyword)) return false;

  const blocked = [
    ...DEFAULT_BLOCKED_TERMS,
    ...extraBlockedTerms.split(",").map(normalizeSearchKeyword),
  ].filter(Boolean);

  const comparable = ` ${keyword.replace(/[^\p{L}\p{N}]+/gu, " ")} `;
  return !blocked.some((term) => {
    const comparableTerm = term.replace(/[^\p{L}\p{N}]+/gu, " ");
    return comparable.includes(` ${comparableTerm} `);
  });
}

/**
 * Rank query momentum, not merely total popularity. The 24-hour signal makes
 * fresh demand react quickly, while the previous seven-day window prevents a
 * permanently popular keyword from monopolising the list.
 */
export function rankTrendingKeywords({
  current7d,
  previous7d,
  recent24h,
  minimumCount = 2,
  limit = 6,
}: {
  current7d: SearchCount[];
  previous7d: SearchCount[];
  recent24h: SearchCount[];
  minimumCount?: number;
  limit?: number;
}): TrendingKeyword[] {
  const previous = new Map(previous7d.map((row) => [row.keyword, row.count]));
  const recent = new Map(recent24h.map((row) => [row.keyword, row.count]));

  return current7d
    .filter(
      (row) => row.count >= minimumCount && isSearchKeywordAllowed(row.keyword)
    )
    .map((row) => {
      const previousCount7d = previous.get(row.keyword) ?? 0;
      const count24h = recent.get(row.keyword) ?? 0;
      const delta = row.count - previousCount7d;
      const growth = (row.count + 1) / (previousCount7d + 1);
      const score =
        row.count +
        count24h * 2 +
        Math.max(0, delta) * 1.5 +
        Math.min(growth, 5);
      return {
        keyword: row.keyword,
        count7d: row.count,
        count24h,
        previousCount7d,
        growth,
        score,
      };
    })
    .sort(
      (a, b) =>
        b.score - a.score ||
        b.count24h - a.count24h ||
        b.count7d - a.count7d ||
        a.keyword.localeCompare(b.keyword, "id-ID")
    )
    .slice(0, limit);
}

export function toSearchDisplayLabel(keyword: string): string {
  return keyword.replace(/(^|[\s-])\p{L}/gu, (letter) =>
    letter.toLocaleUpperCase("id-ID")
  );
}
