import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { pickDosageForWeight, parseDosageRules } from "@/lib/product-dosage";

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
