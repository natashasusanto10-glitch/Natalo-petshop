import { describe, expect, it } from "vitest";
import { canRemoveImage, removeImageAt } from "../lib/product/product-media";

describe("compact product media rail helpers", () => {
  it("removes the cover and promotes the next image", () => {
    expect(removeImageAt(["cover", "second", "third"], 0)).toEqual(["second", "third"]);
  });

  it("blocks deleting the last remaining photo", () => {
    expect(canRemoveImage(["only"])).toBe(false);
  });
});
