export type DosageRule = {
  minKg: number;
  maxKg: number | null;
  instruction: string;
};

export function parseDosageRules(raw: unknown): DosageRule[] {
  if (!Array.isArray(raw)) return [];
  const out: DosageRule[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const { minKg, maxKg, instruction } = item as Record<string, unknown>;
    if (typeof minKg !== "number" || Number.isNaN(minKg)) continue;
    if (!(maxKg === null || (typeof maxKg === "number" && !Number.isNaN(maxKg)))) continue;
    if (typeof instruction !== "string" || !instruction.trim()) continue;
    out.push({ minKg, maxKg: maxKg as number | null, instruction: instruction.trim() });
  }
  return out;
}

export function pickDosageForWeight(
  rules: DosageRule[] | null | undefined,
  weightKg: number | null | undefined,
): DosageRule | null {
  if (!rules || rules.length === 0) return null;
  if (weightKg === null || weightKg === undefined || Number.isNaN(weightKg)) return null;
  for (const r of rules) {
    const underMax = r.maxKg === null || weightKg < r.maxKg;
    if (weightKg >= r.minKg && underMax) return r;
  }
  return null;
}

export type RecoProductInput = {
  id: string;
  name: string;
  price: number;
  baseStock: number;
  variantStocks: number[];
  variantPrices: number[];
  targetSpecies: string[];
  dosageRules: DosageRule[];
};

export function effectiveStock(p: RecoProductInput): number {
  if (p.variantStocks.length > 0) return p.variantStocks.reduce((a, b) => a + b, 0);
  return p.baseStock;
}

export function effectivePrice(p: RecoProductInput): number {
  if (p.variantPrices.length > 0) return Math.min(...p.variantPrices);
  return p.price;
}

export function matchesRecommendation(
  p: RecoProductInput,
  species: string,
  weightKg: number,
): boolean {
  const speciesOk = p.targetSpecies.length === 0 || p.targetSpecies.includes(species);
  if (!speciesOk) return false;
  return pickDosageForWeight(p.dosageRules, weightKg) !== null;
}

export function sortRecommendedProducts(
  products: RecoProductInput[],
  species: string,
  weightKg: number,
): RecoProductInput[] {
  return products
    .filter((p) => matchesRecommendation(p, species, weightKg))
    .sort((a, b) => {
      const aIn = effectiveStock(a) > 0 ? 1 : 0;
      const bIn = effectiveStock(b) > 0 ? 1 : 0;
      if (aIn !== bIn) return bIn - aIn;
      const pd = effectivePrice(a) - effectivePrice(b);
      if (pd !== 0) return pd;
      return a.name.localeCompare(b.name);
    });
}
