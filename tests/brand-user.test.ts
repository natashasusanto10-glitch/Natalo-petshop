import assert from "node:assert/strict";
import test from "node:test";
import {
  OFFICIAL_BRAND_NAME,
  brandDisplayName,
  brandPhotoUrl,
  brandifyUser,
  isAdminRole,
} from "@/lib/social/brand-user";

// ---------------------------------------------------------------------------
// Brand identity guard — akun ADMIN tidak boleh bocorkan nama asli / foto
// pemilik ("Natasha") ke viewer lain. Helper ini dipakai di SEMUA permukaan
// publik (feed, likers, komentar, follow list, notif), jadi perilakunya
// dikunci di sini.
// ---------------------------------------------------------------------------

test("isAdminRole hanya true untuk role ADMIN", () => {
  assert.equal(isAdminRole("ADMIN"), true);
  assert.equal(isAdminRole("CUSTOMER"), false);
  assert.equal(isAdminRole(null), false);
  assert.equal(isAdminRole(undefined), false);
});

test("brandDisplayName: admin → brand name, user → nama asli", () => {
  assert.equal(OFFICIAL_BRAND_NAME, "Natalo Petshop Official");
  assert.equal(brandDisplayName("ADMIN", "Natasha"), OFFICIAL_BRAND_NAME);
  assert.equal(brandDisplayName("CUSTOMER", "Asiong"), "Asiong");
  // Nama asli admin TIDAK boleh muncul, apa pun isinya.
  assert.notEqual(brandDisplayName("ADMIN", "Natasha"), "Natasha");
});

test("brandPhotoUrl: admin → null (klien render logo), user → foto asli", () => {
  assert.equal(brandPhotoUrl("ADMIN", "https://cdn/x/natasha.jpg"), null);
  assert.equal(
    brandPhotoUrl("CUSTOMER", "https://cdn/x/asiong.jpg"),
    "https://cdn/x/asiong.jpg",
  );
});

test("brandifyUser menimpa name+photo untuk admin, sisanya utuh", () => {
  const admin = brandifyUser({
    id: "admin",
    role: "ADMIN",
    name: "Natasha",
    username: "natalopetshop",
    profilePhotoUrl: "https://cdn/x/natasha.jpg",
  });
  assert.equal(admin.name, OFFICIAL_BRAND_NAME);
  assert.equal(admin.profilePhotoUrl, null);
  assert.equal(admin.username, "natalopetshop");
  assert.equal(admin.id, "admin");

  const user = brandifyUser({
    id: "u1",
    role: "CUSTOMER",
    name: "Asiong",
    profilePhotoUrl: "https://cdn/x/asiong.jpg",
  });
  assert.equal(user.name, "Asiong");
  assert.equal(user.profilePhotoUrl, "https://cdn/x/asiong.jpg");
});
