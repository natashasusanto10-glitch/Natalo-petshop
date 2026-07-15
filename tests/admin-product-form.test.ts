import { describe, expect, it } from "vitest";
import { productIsVisibleWhere, shouldDeleteCreatingProduct } from "../lib/product/admin-product-form";

describe("admin product creation lifecycle", () => {
  it("only exposes ready products", () => {
    expect(productIsVisibleWhere()).toEqual({ creationState: "ready" });
  });

  it("deletes only products still being created", () => {
    expect(shouldDeleteCreatingProduct("creating")).toBe(true);
    expect(shouldDeleteCreatingProduct("ready")).toBe(false);
  });
});
