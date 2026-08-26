import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { createBrandSchema, slugifyBrandName } from "../lib/validators/brand-schema";

describe("createBrandSchema", () => {
  it("menerima nama brand yang valid", () => {
    const result = createBrandSchema.safeParse({ name: "Royal Canin" });
    assert.strictEqual(result.success, true);
  });

  it("menolak nama kosong", () => {
    const result = createBrandSchema.safeParse({ name: "" });
    assert.strictEqual(result.success, false);
  });

  it("menolak nama yang hanya berisi spasi", () => {
    const result = createBrandSchema.safeParse({ name: "   " });
    assert.strictEqual(result.success, false);
  });
});

describe("slugifyBrandName", () => {
  it("mengubah nama sederhana jadi slug lowercase-hyphen", () => {
    assert.strictEqual(slugifyBrandName("Royal Canin"), "royal-canin");
  });

  it("mengganti & dengan 'and'", () => {
    assert.strictEqual(slugifyBrandName("Purina & Friends"), "purina-and-friends");
  });

  it("membuang karakter non-alphanumeric dan trim hyphen di ujung", () => {
    assert.strictEqual(slugifyBrandName("  Brand!! Baru??  "), "brand-baru");
  });
});
