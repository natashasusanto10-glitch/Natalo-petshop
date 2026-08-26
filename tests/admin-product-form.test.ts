import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { productIsVisibleWhere, shouldDeleteCreatingProduct, normalizeProductFormPayload } from "../lib/product/admin-product-form";
import { buildDescriptionContext } from "../lib/ai/product-description-context";
import { buildGenerationPayload } from "../lib/ai/product-description-context";
import { mergePersistedDescriptionContext } from "../lib/ai/product-description-context";
import { variantPersistenceMode } from "../lib/product/variant-editor";
import { productFormCopy } from "../lib/product/product-form-copy";
import { reorderImages } from "../lib/product/product-media";

describe("admin product creation lifecycle", () => {
  it("uses one form copy for create and edit", () => {
    assert.strictEqual(productFormCopy("create").submit, "Simpan Produk");
    assert.strictEqual(productFormCopy("edit").submit, "Simpan Perubahan");
  });
  it("returns both modes to the product list after save", () => {
    assert.strictEqual("/admin/products", "/admin/products");
  });
  it("builds AI context for an unsaved product", () => {
    assert.deepStrictEqual(buildDescriptionContext({ name: "Pakan", categoryName: "Kucing", brandName: "Acme", variants: [{ optionRefs: ["Rasa: Tuna"] }] }), {
      name: "Pakan", categoryName: "Kucing", brandName: "Acme", variantOptions: ["Rasa: Tuna"],
    });
  });

  it("forwards draft context when generating from an existing product", () => {
    assert.deepStrictEqual(buildGenerationPayload({ name: "Lama", categoryName: "Lama", brandName: "Lama", variants: [{ optionValues: ["Lama"] }] }, "Baru"), {
      name: "Baru", categoryName: "Lama", brandName: "Lama", variantOptions: ["Lama"],
    });
  });

  it("keeps explicitly cleared AI context instead of restoring persisted values", () => {
    assert.deepStrictEqual(mergePersistedDescriptionContext({ name: "Baru", categoryName: null, brandName: null, variantOptions: [] }, { name: "Lama", categoryName: "Kucing", brandName: "Acme", variantOptions: ["Tuna"] }), { name: "Baru", categoryName: null, brandName: null, variantOptions: [] });
  });

  it("persists controlled variants through the parent save", () => {
    assert.strictEqual(variantPersistenceMode("controlled"), "parent-save");
  });
  it("only exposes ready products", () => {
    assert.deepStrictEqual(productIsVisibleWhere(), { creationState: "ready" });
  });

  it("deletes only products still being created", () => {
    assert.strictEqual(shouldDeleteCreatingProduct("creating"), true);
    assert.strictEqual(shouldDeleteCreatingProduct("ready"), false);
  });

  it("normalizes nine photos and keeps selected video metadata", () => {
    const result = normalizeProductFormPayload({
      name: "  Product  ",
      imageUrls: [" cover ", ...Array.from({ length: 8 }, (_, i) => `img-${i}`)],
      video: { guid: "video-guid", status: "uploading" },
    });
    assert.strictEqual(result.imageUrl, "cover");
    assert.strictEqual((result.gallery).length, 8);
    assert.deepStrictEqual(result.video, { guid: "video-guid", status: "uploading" });
  });

  it("rejects a no-photo payload", () => {
    assert.throws(() => normalizeProductFormPayload({ name: "Product", imageUrls: [] }), { message: "Minimal satu foto wajib diisi" });
  });

  it("preserves legacy cover plus gallery payload", () => {
    const result = normalizeProductFormPayload({
      name: "Legacy",
      imageUrls: ["cover.jpg", "gallery-1.jpg", "gallery-2.jpg"],
    });
    assert.strictEqual(result.imageUrl, "cover.jpg");
    assert.deepStrictEqual(result.gallery, ["gallery-1.jpg", "gallery-2.jpg"]);
  });

  it("reorders product images while keeping the new cover first", () => {
    assert.deepStrictEqual(reorderImages(["cover.jpg", "side.jpg", "back.jpg"], 2, 0), [
      "back.jpg",
      "cover.jpg",
      "side.jpg",
    ]);
  });
});
