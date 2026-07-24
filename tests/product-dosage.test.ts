import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { pickDosageForWeight, parseDosageRules, sortRecommendedProducts, effectiveStock, effectivePrice } from "@/lib/product-dosage";

describe("pickDosageForWeight", () => {
  const rules = [
    { minKg: 0, maxKg: 5, instruction: "1/2 tablet" },
    { minKg: 5, maxKg: 10, instruction: "1 tablet" },
    { minKg: 10, maxKg: null, instruction: "2 tablet" },
  ];
  test("picks the rule whose range includes the weight (upper bound exclusive)", () => {
    assert.equal(pickDosageForWeight(rules, 4.5)?.instruction, "1/2 tablet");
    assert.equal(pickDosageForWeight(rules, 5)?.instruction, "1 tablet");
    assert.equal(pickDosageForWeight(rules, 25)?.instruction, "2 tablet");
  });
  test("returns null when weight or rules missing", () => {
    assert.equal(pickDosageForWeight(rules, null), null);
    assert.equal(pickDosageForWeight(null, 4.5), null);
    assert.equal(pickDosageForWeight([], 4.5), null);
  });
  test("returns null when no range matches", () => {
    assert.equal(pickDosageForWeight([{ minKg: 10, maxKg: 20, instruction: "x" }], 4), null);
  });
});

describe("parseDosageRules", () => {
  test("keeps valid entries and drops malformed ones", () => {
    const raw = [
      { minKg: 0, maxKg: 5, instruction: "a" },
      { minKg: "bad", maxKg: 5, instruction: "b" },
      { minKg: 5, maxKg: null, instruction: "" },
      { minKg: 5, maxKg: null, instruction: "c" },
    ];
    const out = parseDosageRules(raw);
    assert.deepEqual(out, [
      { minKg: 0, maxKg: 5, instruction: "a" },
      { minKg: 5, maxKg: null, instruction: "c" },
    ]);
  });
  test("returns [] for non-array", () => {
    assert.deepEqual(parseDosageRules(null), []);
    assert.deepEqual(parseDosageRules("nope"), []);
  });
});

const base = (over: Partial<any> = {}) => ({
  id: "p", name: "P", price: 50000, baseStock: 0, variantStocks: [], variantPrices: [],
  targetSpecies: ["Anjing"], dosageRules: [{ minKg: 0, maxKg: 10, instruction: "1/2 tablet" }],
  ...over,
});

describe("effectiveStock/effectivePrice", () => {
  test("uses variant totals when variants exist", () => {
    assert.equal(effectiveStock(base({ baseStock: 0, variantStocks: [0, 3] })), 3);
    assert.equal(effectivePrice(base({ price: 50000, variantPrices: [15000, 20000] })), 15000);
  });
  test("falls back to base when no variants", () => {
    assert.equal(effectiveStock(base({ baseStock: 7 })), 7);
    assert.equal(effectivePrice(base({ price: 45000 })), 45000);
  });
});

describe("sortRecommendedProducts", () => {
  test("filters by species+weight and orders in-stock then cheapest", () => {
    const products = [
      base({ id: "cat", targetSpecies: ["Kucing"] }),                 // wrong species
      base({ id: "heavy", dosageRules: [{ minKg: 20, maxKg: null, instruction: "x" }] }), // weight out of range
      base({ id: "pricey", price: 68000, baseStock: 5 }),
      base({ id: "cheap-oos", price: 15000, baseStock: 0 }),          // matches but out of stock
      base({ id: "cheap-in", price: 45000, baseStock: 2 }),
    ];
    const out = sortRecommendedProducts(products, "Anjing", 4.5).map((p) => p.id);
    assert.deepEqual(out, ["cheap-in", "pricey", "cheap-oos"]);
  });
  test("treats empty targetSpecies as matching any species", () => {
    const out = sortRecommendedProducts([base({ id: "any", targetSpecies: [] })], "Reptil", 4.5);
    assert.deepEqual(out.map((p) => p.id), ["any"]);
  });
});
