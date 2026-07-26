import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { validateCarePayload, computeUpcoming, CARE_CATEGORIES } from "@/lib/pet-care-api";

describe("validateCarePayload", () => {
  test("rejects non-object", () => {
    assert.deepEqual(validateCarePayload(null), {
      error: "Data perawatan tidak terkirim dengan benar. Coba ulangi.",
    });
  });
  test("rejects unknown category", () => {
    assert.deepEqual(
      validateCarePayload({ category: "spa", doneAt: "2026-07-01" }),
      { error: "Jenis perawatan tidak valid." },
    );
  });
  test("rejects missing/invalid doneAt", () => {
    assert.deepEqual(
      validateCarePayload({ category: "grooming", doneAt: "bogus" }),
      { error: "Tanggal perawatan tidak valid." },
    );
  });
  test("rejects note over 200 chars", () => {
    const r = validateCarePayload({ category: "grooming", doneAt: "2026-07-01", note: "x".repeat(201) });
    assert.deepEqual(r, { error: "Catatan maksimal 200 karakter." });
  });
  test("rejects nextDueAt not after doneAt", () => {
    const r = validateCarePayload({ category: "grooming", doneAt: "2026-07-10", nextDueAt: "2026-07-10" });
    assert.deepEqual(r, { error: "Jadwal berikutnya harus setelah tanggal perawatan." });
  });
  test("accepts a full valid payload and trims note", () => {
    const r = validateCarePayload({ category: "flea", doneAt: "2026-07-01", note: "  Frontline  ", nextDueAt: "2026-08-01" });
    assert.equal("data" in r && r.data.category, "flea");
    assert.equal("data" in r && r.data.note, "Frontline");
    assert.equal("data" in r && r.data.nextDueAt instanceof Date, true);
  });
  test("maps empty note to null", () => {
    const r = validateCarePayload({ category: "vet", doneAt: "2026-07-01", note: "   " });
    assert.equal("data" in r && r.data.note, null);
  });
  test("exposes all 6 categories", () => {
    assert.deepEqual([...CARE_CATEGORIES].sort(), ["deworm", "flea", "grooming", "other", "vaccine", "vet"]);
  });
});

describe("computeUpcoming (supersede rule)", () => {
  const d = (s: string) => new Date(s);
  test("returns the schedule when not superseded", () => {
    const rows = [{ id: "a", category: "grooming", doneAt: d("2026-06-01"), nextDueAt: d("2026-09-01") }];
    assert.deepEqual(computeUpcoming(rows), [{ recordId: "a", category: "grooming", nextDueAt: d("2026-09-01") }]);
  });
  test("supersedes an older schedule when a newer same-category record exists", () => {
    const rows = [
      { id: "a", category: "grooming", doneAt: d("2026-06-01"), nextDueAt: d("2026-09-01") },
      { id: "b", category: "grooming", doneAt: d("2026-07-01"), nextDueAt: null },
    ];
    assert.deepEqual(computeUpcoming(rows), []);
  });
  test("keeps schedules from different categories independent", () => {
    const rows = [
      { id: "a", category: "grooming", doneAt: d("2026-06-01"), nextDueAt: d("2026-09-01") },
      { id: "b", category: "flea", doneAt: d("2026-06-15"), nextDueAt: d("2026-07-15") },
    ];
    const out = computeUpcoming(rows);
    assert.deepEqual(out.map((x) => x.category), ["flea", "grooming"]);
  });
  test("ignores records without nextDueAt", () => {
    const rows = [{ id: "a", category: "vet", doneAt: d("2026-06-01"), nextDueAt: null }];
    assert.deepEqual(computeUpcoming(rows), []);
  });
});

describe("validateCarePayload — new optional fields", () => {
  const okBase = { category: "deworm", doneAt: "2026-07-24T00:00:00.000Z" };

  test("accepts and normalizes new fields", () => {
    const r = validateCarePayload({
      ...okBase, weightKg: 4.5, productId: "prod1", place: "  Natalo  ",
      vaccineName: "", complaint: "  Gatal  ",
    });
    assert.equal("data" in r, true);
    if ("data" in r) {
      assert.equal(r.data.weightKg, 4.5);
      assert.equal(r.data.productId, "prod1");
      assert.equal(r.data.place, "Natalo");
      assert.equal(r.data.vaccineName, null);
      assert.equal(r.data.complaint, "Gatal");
    }
  });

  test("rejects negative or absurd weight", () => {
    assert.equal("error" in validateCarePayload({ ...okBase, weightKg: -1 }), true);
    assert.equal("error" in validateCarePayload({ ...okBase, weightKg: 999 }), true);
  });

  test("keeps working with no new fields (Tahap 3 payload)", () => {
    const r = validateCarePayload({ category: "grooming", doneAt: okBase.doneAt });
    assert.equal("data" in r, true);
    if ("data" in r) assert.equal(r.data.weightKg, null);
  });
});
