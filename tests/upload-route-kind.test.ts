import assert from "node:assert/strict";
import test from "node:test";
import { resolveUploadKind } from "@/app/api/admin/upload/route";

test("resolveUploadKind defaults to product when kind is missing", () => {
  assert.equal(resolveUploadKind(null), "product");
});

test("resolveUploadKind defaults to product for unknown values", () => {
  assert.equal(resolveUploadKind("banner" as unknown as FormDataEntryValue), "product");
});

test("resolveUploadKind recognizes brand-logo", () => {
  assert.equal(resolveUploadKind("brand-logo" as unknown as FormDataEntryValue), "brand-logo");
});
