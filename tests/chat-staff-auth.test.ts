import assert from "node:assert/strict";
import test from "node:test";
import { isPaymentStaffAuthorized, isStaffAuthorized } from "@/lib/chat/staff-auth";

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

test("verifikasi pembayaran membutuhkan owner atau capability eksplisit", () => {
  assert.equal(isPaymentStaffAuthorized({ role: "owner" }), true);
  assert.equal(isPaymentStaffAuthorized({ role: "karyawan", canVerifyPayments: true }), true);
  assert.equal(isPaymentStaffAuthorized({ role: "karyawan", canVerifyPayments: false }), false);
  assert.equal(isPaymentStaffAuthorized({ role: "karyawan" }), false);
  assert.equal(isPaymentStaffAuthorized(null), false);
});

test("hak chat tidak otomatis memberi hak finansial", () => {
  const support = { role: "karyawan", canHandleCustomer: true };
  assert.equal(isStaffAuthorized(support), true);
  assert.equal(isPaymentStaffAuthorized(support), false);
});
