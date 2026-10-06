import { seededShuffle } from "./recommendation-rotation";

/** Rotate within a relevance pool, spreading brands instead of repeating one. */
export function rotateRecommendationPool<T extends { id: string; brandId?: string | null }>(
  candidates: T[], seed: string, limit: number,
): T[] {
  if (!seed) return candidates.slice(0, limit);
  const groups = new Map<string, T[]>();
  const seen = new Set<string>();
  for (const product of seededShuffle(candidates, seed)) {
    if (seen.has(product.id)) continue;
    seen.add(product.id);
    const key = product.brandId ?? product.id;
    const group = groups.get(key) ?? [];
    group.push(product);
    groups.set(key, group);
  }
  const result: T[] = [];
  while (result.length < limit) {
    let added = false;
    for (const group of groups.values()) {
      const product = group.shift();
      if (!product) continue;
      result.push(product);
      added = true;
      if (result.length === limit) break;
    }
    if (!added) break;
  }
  return result;
}
