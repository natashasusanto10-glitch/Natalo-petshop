import assert from "node:assert/strict";
import test from "node:test";
import { isStaffAuthorized } from "@/lib/chat/staff-auth";

test("owner selalu boleh", () => {
  assert.equal(isStaffAuthorized({ role: "owner" }), true);
});
test("karyawan + canHandleCustomer boleh", () => {
  assert.equal(isStaffAuthorized({ role: "karyawan", canHandleCustomer: true }), true);
});
test("karyawan tanpa flag ditolak", () => {
  assert.equal(isStaffAuthorized({ role: "karyawan" }), false);
  assert.equal(isStaffAuthorized({ role: "karyawan", canHandleCustomer: false }), false);
});
test("doc null / kosong ditolak", () => {
  assert.equal(isStaffAuthorized(null), false);
  assert.equal(isStaffAuthorized({}), false);
});
