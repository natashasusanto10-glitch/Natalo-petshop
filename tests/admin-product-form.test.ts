import { describe, expect, it } from "vitest";
import { productIsVisibleWhere, shouldDeleteCreatingProduct, normalizeProductFormPayload } from "../lib/product/admin-product-form";
import { buildDescriptionContext } from "../lib/ai/product-description-context";
import { buildGenerationPayload } from "../lib/ai/product-description-context";
import { variantPersistenceMode } from "../lib/product/variant-editor";

describe("admin product creation lifecycle", () => {
  it("builds AI context for an unsaved product", () => {
    expect(buildDescriptionContext({ name: "Pakan", categoryName: "Kucing", brandName: "Acme", variants: [{ optionRefs: ["Rasa: Tuna"] }] })).toEqual({
      name: "Pakan", categoryName: "Kucing", brandName: "Acme", variantOptions: ["Rasa: Tuna"],
    });
  });

  it("forwards draft context when generating from an existing product", () => {
    expect(buildGenerationPayload({ name: "Lama", categoryName: "Lama", brandName: "Lama", variants: [{ optionValues: ["Lama"] }] }, "Baru")).toEqual({
      name: "Baru", categoryName: "Lama", brandName: "Lama", variantOptions: ["Lama"],
    });
  });

  it("persists controlled variants through the parent save", () => {
    expect(variantPersistenceMode("controlled")).toBe("parent-save");
  });
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

  it("preserves legacy cover plus gallery payload", () => {
    const result = normalizeProductFormPayload({
      name: "Legacy",
      imageUrls: ["cover.jpg", "gallery-1.jpg", "gallery-2.jpg"],
    });
    expect(result.imageUrl).toBe("cover.jpg");
    expect(result.gallery).toEqual(["gallery-1.jpg", "gallery-2.jpg"]);
  });
});
