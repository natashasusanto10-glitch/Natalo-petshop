import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { nextVideoMutation, resolveHiddenCreateFailure } from "../lib/product/product-video-draft";

describe("product video draft compensation", () => {
  it("preserves existing video until parent save succeeds", () => {
    assert.deepStrictEqual(nextVideoMutation({ existingGuid: "old", removeRequested: true, saveSucceeded: false }), {
      deleteGuid: null,
      preserveGuid: "old",
    });
  });

  it("compensates a hidden product when upload fails", () => {
    assert.deepStrictEqual(resolveHiddenCreateFailure({ productId: "p1", uploadSucceeded: false }), {
      compensateProductId: "p1",
    });
  });

  it("also targets a newly provisioned guid when an edit replacement fails", () => {
    assert.deepStrictEqual(resolveHiddenCreateFailure({ productId: "new-guid", uploadSucceeded: false }), {
      compensateProductId: "new-guid",
    });
  });
});
