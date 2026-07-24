import test from "node:test";
import assert from "node:assert/strict";
import {
  extractHashtags,
  isValidHashtagName,
  MAX_HASHTAGS_PER_POST,
  HASHTAG_LIMIT_MESSAGE,
} from "../lib/feed/hashtags";

test("extractHashtags: dasar — lowercase, urutan kemunculan", () => {
  assert.deepEqual(extractHashtags("Halo #KucingLucu dan #anjing_kecil"), [
    "kucinglucu",
    "anjing_kecil",
  ]);
});

test("extractHashtags: boundary — mid-word & URL fragment ditolak", () => {
  assert.deepEqual(extractHashtags("harga#promo cek natalo.com/#promo"), []);
  assert.deepEqual(extractHashtags("#promo di awal teks"), ["promo"]);
  assert.deepEqual(extractHashtags("baris\n#baru juga valid"), ["baru"]);
});

test("extractHashtags: panjang 2-50 di-filter", () => {
  assert.deepEqual(extractHashtags("#a #ab"), ["ab"]);
  const long = "x".repeat(51);
  const max = "y".repeat(50);
  assert.deepEqual(extractHashtags(`#${long} #${max}`), [max]);
});

test("extractHashtags: dedup case-insensitive, sekali hitung", () => {
  assert.deepEqual(extractHashtags("#Kucing #kucing #KUCING #lain"), [
    "kucing",
    "lain",
  ]);
});

test("extractHashtags: angka & underscore boleh; teks kosong aman", () => {
  assert.deepEqual(extractHashtags("#tag_2026 ok"), ["tag_2026"]);
  assert.deepEqual(extractHashtags(""), []);
});

test("isValidHashtagName: hanya nama kanonik yang lolos", () => {
  assert.equal(isValidHashtagName("kucing_2"), true);
  assert.equal(isValidHashtagName("ab"), true);
  assert.equal(isValidHashtagName("a"), false);
  assert.equal(isValidHashtagName("Kucing"), false); // wajib lowercase
  assert.equal(isValidHashtagName("ku cing"), false);
  assert.equal(isValidHashtagName("x".repeat(51)), false);
});

test("konstanta limit & pesan sesuai spec", () => {
  assert.equal(MAX_HASHTAGS_PER_POST, 5);
  assert.equal(HASHTAG_LIMIT_MESSAGE, "Maksimal 5 hashtag per postingan.");
});
