import test from "node:test";
import assert from "node:assert/strict";
import {
  etalaseHeading,
  etalaseTagline,
  ETALASE_TRUST,
  NATALO_RATING,
} from "../lib/etalase";

test("etalaseHeading: search query wins over everything", () => {
  assert.equal(
    etalaseHeading({ isSearch: true, query: "kucing", brandName: "Whiskas" }),
    'Hasil untuk "kucing"',
  );
});

test("etalaseHeading: brand takes precedence over category", () => {
  assert.equal(
    etalaseHeading({ brandName: "Royal Canin", categoryName: "Anjing" }),
    "Produk Royal Canin",
  );
});

test("etalaseHeading: category when no brand/search", () => {
  assert.equal(etalaseHeading({ categoryName: "Aquarium" }), "Aquarium");
});

test("etalaseHeading: default catalog label", () => {
  assert.equal(etalaseHeading({}), "Katalog Produk");
});

test("etalaseTagline: default mentions Medan store", () => {
  assert.match(etalaseTagline({}), /Medan/);
});

test("trust claims are the owner-confirmed set incl. rating", () => {
  assert.deepEqual(ETALASE_TRUST, [
    "Kirim hari ini se-Medan",
    "100% Original",
    "Toko fisik sejak 2018",
  ]);
  assert.equal(NATALO_RATING, "4.9");
});
