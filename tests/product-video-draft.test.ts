import { describe, expect, it } from "vitest";
import { nextVideoMutation, resolveHiddenCreateFailure } from "../lib/product/product-video-draft";

describe("product video draft compensation", () => {
  it("preserves existing video until parent save succeeds", () => {
    expect(nextVideoMutation({ existingGuid: "old", removeRequested: true, saveSucceeded: false })).toEqual({
      deleteGuid: null,
      preserveGuid: "old",
    });
  });

  it("compensates a hidden product when upload fails", () => {
    expect(resolveHiddenCreateFailure({ productId: "p1", uploadSucceeded: false })).toEqual({
      compensateProductId: "p1",
    });
  });

  it("also targets a newly provisioned guid when an edit replacement fails", () => {
    expect(resolveHiddenCreateFailure({ productId: "new-guid", uploadSucceeded: false })).toEqual({
      compensateProductId: "new-guid",
    });
  });
});
