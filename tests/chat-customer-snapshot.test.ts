import assert from "node:assert/strict";
import test from "node:test";
import { pickCustomerName, pickCustomerPhone } from "@/lib/chat/customer-snapshot";

test("nama akun dipakai bila ada; kalau kosong pakai nama saat checkout", () => {
  assert.equal(pickCustomerName("Susanto", "Budi"), "Susanto");
  assert.equal(pickCustomerName("  ", " Budi Santoso "), "Budi Santoso");
  assert.equal(pickCustomerName(null, "Budi"), "Budi");
  assert.equal(pickCustomerName(undefined, null), "");
  assert.equal(pickCustomerName("", ""), "");
});

test("nomor HP akun dipakai bila ada; kalau kosong pakai nomor saat checkout", () => {
  assert.equal(pickCustomerPhone("0812", "0899"), "0812");
  assert.equal(pickCustomerPhone(" ", " 0899 "), "0899");
  assert.equal(pickCustomerPhone(null, undefined), "");
});
