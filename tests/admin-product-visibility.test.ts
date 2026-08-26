import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { cleanupWhere, mergeProductVisibility } from "../lib/product/admin-product-form";

describe("product visibility", () => {
  it("merges ready creation state without dropping existing conditions", () => {
    assert.deepStrictEqual(mergeProductVisibility({ isActive: true }), { isActive: true, creationState: "ready" });
  });

  it("selects only creating products older than one hour", () => {
    const now = new Date("2026-07-15T12:00:00.000Z");
    assert.deepStrictEqual(cleanupWhere(now), {
      creationState: "creating",
      createdAt: { lt: new Date("2026-07-15T11:00:00.000Z") },
    });
  });
});
