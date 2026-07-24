export type DosageRule = {
  minKg: number;
  maxKg: number | null;
  instruction: string;
};

const CARE_CATEGORIES = new Set(["deworm", "flea"]);

/**
 * Validasi manual field "Perawatan (obat)" dari admin product API
 * (create+PATCH, Task 9). Dipakai bersama supaya aturan konsisten:
 * - careCategory harus null / "deworm" / "flea".
 * - targetSpecies harus array of string (default []).
 * - dosageRules harus array of {minKg:number, maxKg:number|null,
 *   instruction:non-empty string} (default null bila careCategory kosong).
 *
 * Return null (gagal validasi → sertakan `error` message) atau object
 * ternormalisasi siap ditulis ke Prisma.
 */
export function validateCareFields(body: Record<string, unknown>):
  | { ok: true; careCategory: string | null; targetSpecies: string[]; dosageRules: DosageRule[] | null }
  | { ok: false; error: string } {
  let careCategory: string | null = null;
  if (typeof body.careCategory === "string" && body.careCategory.trim()) {
    if (!CARE_CATEGORIES.has(body.careCategory.trim())) {
      return { ok: false, error: `careCategory harus "deworm" atau "flea".` };
    }
    careCategory = body.careCategory.trim();
  } else if (body.careCategory !== undefined && body.careCategory !== null && body.careCategory !== "") {
    return { ok: false, error: `careCategory harus "deworm" atau "flea".` };
  }

  if (!careCategory) {
    return { ok: true, careCategory: null, targetSpecies: [], dosageRules: null };
  }

  const targetSpeciesRaw = body.targetSpecies;
  let targetSpecies: string[] = [];
  if (targetSpeciesRaw !== undefined) {
    if (!Array.isArray(targetSpeciesRaw) || !targetSpeciesRaw.every((s) => typeof s === "string")) {
      return { ok: false, error: "targetSpecies harus array of string." };
    }
    targetSpecies = targetSpeciesRaw as string[];
  }

  const dosageRulesRaw = body.dosageRules;
  let dosageRules: DosageRule[] | null = null;
  if (dosageRulesRaw !== undefined && dosageRulesRaw !== null) {
    if (!Array.isArray(dosageRulesRaw)) {
      return { ok: false, error: "dosageRules harus array." };
    }
    const parsed: DosageRule[] = [];
    for (const item of dosageRulesRaw) {
      if (typeof item !== "object" || item === null) return { ok: false, error: "Setiap dosageRules harus object." };
      const { minKg, maxKg, instruction } = item as Record<string, unknown>;
      if (typeof minKg !== "number" || Number.isNaN(minKg)) return { ok: false, error: "dosageRules.minKg harus number." };
      if (!(maxKg === null || maxKg === undefined || (typeof maxKg === "number" && !Number.isNaN(maxKg)))) {
        return { ok: false, error: "dosageRules.maxKg harus number atau null." };
      }
      if (typeof instruction !== "string" || !instruction.trim()) return { ok: false, error: "dosageRules.instruction wajib diisi." };
      parsed.push({ minKg, maxKg: maxKg === undefined ? null : (maxKg as number | null), instruction: instruction.trim() });
    }
    dosageRules = parsed;
  }

  return { ok: true, careCategory, targetSpecies, dosageRules };
}

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
