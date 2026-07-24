import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { validatePetPayload } from "@/lib/pets-api";

const base = { name: "Milo", type: "Kucing" };

describe("validatePetPayload health fields", () => {
  test("defaults health fields to null when absent", () => {
    const r = validatePetPayload(base);
    assert.ok("data" in r);
    assert.equal(r.data.sterilized, null);
    assert.equal(r.data.allergy, null);
    assert.equal(r.data.healthNote, null);
  });
  test("accepts sterilized boolean", () => {
    const r = validatePetPayload({ ...base, sterilized: true });
    assert.ok("data" in r);
    assert.equal(r.data.sterilized, true);
  });
  test("trims allergy and rejects over 100 chars", () => {
    assert.deepEqual(
      validatePetPayload({ ...base, allergy: "x".repeat(101) }),
      { error: "Alergi maksimal 100 karakter." },
    );
    const r = validatePetPayload({ ...base, allergy: "  Ayam  " });
    assert.ok("data" in r);
    assert.equal(r.data.allergy, "Ayam");
  });
  test("rejects healthNote over 150 chars", () => {
    assert.deepEqual(
      validatePetPayload({ ...base, healthNote: "x".repeat(151) }),
      { error: "Kondisi khusus maksimal 150 karakter." },
    );
  });
});
