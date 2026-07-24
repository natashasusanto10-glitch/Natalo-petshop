import { describe, it, expect } from "vitest";
import { pickDosageForWeight, parseDosageRules } from "@/lib/product-dosage";

describe("pickDosageForWeight", () => {
  const rules = [
    { minKg: 0, maxKg: 5, instruction: "1/2 tablet" },
    { minKg: 5, maxKg: 10, instruction: "1 tablet" },
    { minKg: 10, maxKg: null, instruction: "2 tablet" },
  ];
  it("picks the rule whose range includes the weight (upper bound exclusive)", () => {
    expect(pickDosageForWeight(rules, 4.5)?.instruction).toBe("1/2 tablet");
    expect(pickDosageForWeight(rules, 5)?.instruction).toBe("1 tablet");
    expect(pickDosageForWeight(rules, 25)?.instruction).toBe("2 tablet");
  });
  it("returns null when weight or rules missing", () => {
    expect(pickDosageForWeight(rules, null)).toBeNull();
    expect(pickDosageForWeight(null, 4.5)).toBeNull();
    expect(pickDosageForWeight([], 4.5)).toBeNull();
  });
  it("returns null when no range matches", () => {
    expect(pickDosageForWeight([{ minKg: 10, maxKg: 20, instruction: "x" }], 4)).toBeNull();
  });
});

describe("parseDosageRules", () => {
  it("keeps valid entries and drops malformed ones", () => {
    const raw = [
      { minKg: 0, maxKg: 5, instruction: "a" },
      { minKg: "bad", maxKg: 5, instruction: "b" },
      { minKg: 5, maxKg: null, instruction: "" },
      { minKg: 5, maxKg: null, instruction: "c" },
    ];
    const out = parseDosageRules(raw);
    expect(out).toEqual([
      { minKg: 0, maxKg: 5, instruction: "a" },
      { minKg: 5, maxKg: null, instruction: "c" },
    ]);
  });
  it("returns [] for non-array", () => {
    expect(parseDosageRules(null)).toEqual([]);
    expect(parseDosageRules("nope")).toEqual([]);
  });
});
