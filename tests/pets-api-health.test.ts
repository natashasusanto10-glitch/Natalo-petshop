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

describe("validatePetPayload type: canonical + legacy grandfather", () => {
  test("accepts the 5 new canonical species (Hamster, Kelinci included)", () => {
    for (const type of ["Kucing", "Anjing", "Hamster", "Kelinci", "Ikan"]) {
      const r = validatePetPayload({ ...base, type });
      assert.ok("data" in r, `${type} harus valid`);
      assert.equal(r.data.type, type);
    }
  });
  test("legacy types (Burung/Reptil/Lainnya) still validate on write — grandfathered, not removable from dropdown users' existing pets", () => {
    for (const type of ["Burung", "Reptil", "Lainnya"]) {
      const r = validatePetPayload({ ...base, type });
      assert.ok(
        "data" in r,
        `${type} adalah jenis lama yang sudah tak jadi opsi dropdown baru, tapi WAJIB tetap valid untuk edit pet lama`,
      );
      assert.equal(r.data.type, type);
    }
  });
  test("rejects a genuinely unknown type", () => {
    assert.deepEqual(validatePetPayload({ ...base, type: "Naga" }), {
      error: "Jenis pet tidak valid.",
    });
  });
});
