import { describe, expect, it } from "vitest";
import { createBrandSchema, slugifyBrandName } from "../lib/validators/brand-schema";

describe("createBrandSchema", () => {
  it("menerima nama brand yang valid", () => {
    const result = createBrandSchema.safeParse({ name: "Royal Canin" });
    expect(result.success).toBe(true);
  });

  it("menolak nama kosong", () => {
    const result = createBrandSchema.safeParse({ name: "" });
    expect(result.success).toBe(false);
  });

  it("menolak nama yang hanya berisi spasi", () => {
    const result = createBrandSchema.safeParse({ name: "   " });
    expect(result.success).toBe(false);
  });
});

describe("slugifyBrandName", () => {
  it("mengubah nama sederhana jadi slug lowercase-hyphen", () => {
    expect(slugifyBrandName("Royal Canin")).toBe("royal-canin");
  });

  it("mengganti & dengan 'and'", () => {
    expect(slugifyBrandName("Purina & Friends")).toBe("purina-and-friends");
  });

  it("membuang karakter non-alphanumeric dan trim hyphen di ujung", () => {
    expect(slugifyBrandName("  Brand!! Baru??  ")).toBe("brand-baru");
  });
});
