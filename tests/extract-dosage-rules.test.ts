import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { parseModelJson } from "@/lib/ai/extract-dosage-rules";

describe("parseModelJson", () => {
  test("parses a bare JSON array", () => {
    assert.deepEqual(
      parseModelJson('[{"minKg":0,"maxKg":5,"instruction":"1/2 tablet"}]'),
      [{ minKg: 0, maxKg: 5, instruction: "1/2 tablet" }],
    );
  });
  test("strips markdown fences", () => {
    const t = "```json\n[{\"minKg\":0,\"maxKg\":null,\"instruction\":\"x\"}]\n```";
    assert.deepEqual(parseModelJson(t), [{ minKg: 0, maxKg: null, instruction: "x" }]);
  });
  test("returns null on non-JSON", () => {
    assert.equal(parseModelJson("tidak ada aturan pakai"), null);
  });
});
