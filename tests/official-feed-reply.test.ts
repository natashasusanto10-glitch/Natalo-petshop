import assert from "node:assert/strict";
import test from "node:test";
import {
  OFFICIAL_BRAND_NAME,
  brandDisplayName,
  brandPhotoUrl,
} from "@/lib/social/brand-user";

test("admin comments render as Natalo Official without staff identity", () => {
  assert.equal(brandDisplayName("ADMIN", "Private Staff"), OFFICIAL_BRAND_NAME);
  assert.equal(brandPhotoUrl("ADMIN", "https://cdn.example/private.jpg"), null);
});

test("customer comment identity and photo pass through unchanged", () => {
  assert.equal(brandDisplayName("CUSTOMER", "Asiong"), "Asiong");
  assert.equal(
    brandPhotoUrl("CUSTOMER", "https://cdn.example/asiong.jpg"),
    "https://cdn.example/asiong.jpg",
  );
});
