import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { mapProductToReco } from "@/app/api/products/care-recommendation/route";

describe("mapProductToReco", () => {
  test("aggregates variant stock/price and picks dosage instruction", () => {
    const row = {
      id: "p1",
      name: "Drontal",
      imageUrl: "x.jpg",
      price: 45000,
      stock: 0,
      dosageRules: [{ minKg: 0, maxKg: 10, instruction: "1/2 tablet" }],
      targetSpecies: ["Anjing"],
      variants: [{ price: 45000, stock: 3 }],
    };
    const out = mapProductToReco(row as any, 4.5);
    assert.deepEqual(out, {
      id: "p1",
      name: "Drontal",
      imageUrl: "x.jpg",
      effectivePrice: 45000,
      inStock: true,
      instruction: "1/2 tablet",
    });
  });

  test("omits instruction when weight is null", () => {
    const row = {
      id: "p",
      name: "N",
      imageUrl: null,
      price: 10000,
      stock: 5,
      dosageRules: [],
      targetSpecies: [],
      variants: [],
    };
    assert.equal(mapProductToReco(row as any, null).instruction, null);
  });
});
