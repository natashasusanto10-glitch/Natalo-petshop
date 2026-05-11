export function buildKeywordOnlySearchParams(keyword: string) {
  const params = new URLSearchParams();
  const trimmed = keyword.trim();
  if (trimmed) params.set("q", trimmed);
  return params;
}

export function buildSearchHrefFromParams(params: URLSearchParams) {
  const query = params.toString();
  return query ? `/search?${query}` : "/search";
}

export function buildKeywordOnlySearchHref(keyword: string) {
  return buildSearchHrefFromParams(buildKeywordOnlySearchParams(keyword));
}
