import { describe, expect, it } from "vitest";
import { canRemoveImage, removeImageAt } from "../lib/product/product-media";
import { uploadProductImageFiles } from "../components/MultiImageUpload";

describe("compact product media rail helpers", () => {
  it("removes the cover and promotes the next image", () => {
    expect(removeImageAt(["cover", "second", "third"], 0)).toEqual(["second", "third"]);
  });

  it("blocks deleting the last remaining photo", () => {
    expect(canRemoveImage(["only"])).toBe(false);
  });

  it("rejects oversized files before upload", async () => {
    const oversized = new File([new Uint8Array(2 * 1024 * 1024 + 1)], "large.jpg", { type: "image/jpeg" });
    const result = await uploadProductImageFiles([oversized], 9);
    expect(result.uploaded).toEqual([]);
    expect(result.failed).toEqual(["large.jpg"]);
  });
});
