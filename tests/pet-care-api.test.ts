import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { validateCarePayload, computeUpcoming, CARE_CATEGORIES } from "@/lib/pet-care-api";

describe("validateCarePayload", () => {
  test("rejects non-object", () => {
    assert.deepEqual(validateCarePayload(null), { error: "Payload tidak valid." });
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
