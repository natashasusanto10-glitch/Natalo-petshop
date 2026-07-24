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
