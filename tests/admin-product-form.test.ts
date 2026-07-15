import { describe, expect, it } from "vitest";
import { productIsVisibleWhere, shouldDeleteCreatingProduct, normalizeProductFormPayload } from "../lib/product/admin-product-form";

describe("admin product creation lifecycle", () => {
  it("only exposes ready products", () => {
    expect(productIsVisibleWhere()).toEqual({ creationState: "ready" });
  });

  it("deletes only products still being created", () => {
    expect(shouldDeleteCreatingProduct("creating")).toBe(true);
    expect(shouldDeleteCreatingProduct("ready")).toBe(false);
  });

  it("normalizes nine photos and keeps selected video metadata", () => {
    const result = normalizeProductFormPayload({
      name: "  Product  ",
      imageUrls: [" cover ", ...Array.from({ length: 8 }, (_, i) => `img-${i}`)],
      video: { guid: "video-guid", status: "uploading" },
    });
    expect(result.imageUrl).toBe("cover");
    expect(result.gallery).toHaveLength(8);
    expect(result.video).toEqual({ guid: "video-guid", status: "uploading" });
  });

  it("rejects a no-photo payload", () => {
    expect(() => normalizeProductFormPayload({ name: "Product", imageUrls: [] })).toThrow(
      "Minimal satu foto wajib diisi",
    );
  });
});
