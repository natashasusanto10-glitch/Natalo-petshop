import assert from "node:assert/strict";
import test from "node:test";
import { pickCustomerName } from "@/lib/chat/customer-snapshot";

test("nama akun dipakai bila ada; kalau kosong pakai nama saat checkout", () => {
  assert.equal(pickCustomerName("Susanto", "Budi"), "Susanto");
  assert.equal(pickCustomerName("  ", " Budi Santoso "), "Budi Santoso");
  assert.equal(pickCustomerName(null, "Budi"), "Budi");
  assert.equal(pickCustomerName(undefined, null), "");
  assert.equal(pickCustomerName("", ""), "");
});
