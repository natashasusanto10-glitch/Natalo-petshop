import assert from "node:assert/strict";
import test from "node:test";

import {
  APP_STORE_URL,
  PLAY_STORE_URL,
  buildAndroidIntentUrl,
  desktopStoreUrl,
} from "@/components/open-in-app";
import { shouldHideBottomNav } from "@/lib/navigation";

test("intent:// Android membawa path + fallback Play Store", () => {
  const url = buildAndroidIntentUrl("/feed/abc123");
  assert.match(url, /^intent:\/\/www\.natalopetshop\.com\/feed\/abc123#Intent;/);
  assert.match(url, /package=com\.natalo\.petshop;/);
  // Tanpa fallback, Android tanpa app cuma dapat error "activity not found".
  assert.ok(url.includes(`S.browser_fallback_url=${encodeURIComponent(PLAY_STORE_URL)}`));
  // Path tanpa garis miring depan tetap dinormalkan.
  assert.match(buildAndroidIntentUrl("u/natalo"), /natalopetshop\.com\/u\/natalo#/);
});

test("desktop diarahkan ke toko sesuai OS — Mac BUKAN ke Play Store", () => {
  // Bug lama: semua non-Android non-iOS dilempar ke Play Store, termasuk
  // pengguna Mac yang jelas-jelas pemilik iPhone lebih mungkin.
  assert.equal(
    desktopStoreUrl("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"),
    APP_STORE_URL,
  );
  assert.equal(
    desktopStoreUrl("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"),
    PLAY_STORE_URL,
  );
  assert.equal(desktopStoreUrl("Mozilla/5.0 (X11; Linux x86_64)"), PLAY_STORE_URL);
});

test("halaman share menyembunyikan bottom nav — pola sama dengan detail produk", () => {
  // Tanpa ini StickyOpenInAppBar tertutup nav situs (nav z-100 vs bar
  // z-40, dibuktikan runtime di viewport 375x812).
  assert.equal(shouldHideBottomNav("/feed/cmt31x60u0002if04en7mh0os"), true);
  assert.equal(shouldHideBottomNav("/u/natalopetshop"), true);
  // Root TIDAK ikut: tab Feed dan daftar-u tetap butuh navigasi utama.
  assert.equal(shouldHideBottomNav("/feed"), false);
  assert.equal(shouldHideBottomNav("/u"), false);
});
