export type FacetOption = {
  slug: string;
  name: string;
  count: number;
};

export function hydrateFacetDistribution(
  distribution: Record<string, number> | undefined,
  labelsBySlug: Map<string, string>,
) {
  return Object.entries(distribution ?? {})
    .filter(([slug, count]) => Boolean(slug) && count > 0 && labelsBySlug.has(slug))
    .map(([slug, count]) => ({
      slug,
      name: labelsBySlug.get(slug)!,
      count,
    }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

export function buildWeightBuckets(distribution: Record<string, number> | undefined) {
  const allWeights = Object.entries(distribution ?? {})
    .map(([weight, count]) => ({ weight: Number(weight), count }))
    .filter((item) => Number.isFinite(item.weight));

  const countWeights = (predicate: (weight: number) => boolean) =>
    allWeights
      .filter((item) => predicate(item.weight))
      .reduce((sum, item) => sum + item.count, 0);

  return [
    { label: "< 1 KG", min: 0, max: 999, count: countWeights((weight) => weight < 1000) },
    {
      label: "1 - 5 KG",
      min: 1000,
      max: 5000,
      count: countWeights((weight) => weight >= 1000 && weight <= 5000),
    },
    { label: "> 5 KG", min: 5001, max: 999999, count: countWeights((weight) => weight > 5000) },
  ];
}
