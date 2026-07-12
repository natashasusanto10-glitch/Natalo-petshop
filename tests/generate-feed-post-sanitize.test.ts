import { test } from "node:test";
import assert from "node:assert/strict";
import { sanitizeCaption } from "../lib/ai/generate-feed-post";

// Regresi bug nyata: caption AI dibuka dengan "# <judul ulang> <emoji>"
// (gaya heading IG) lalu ditutup belasan hashtag → judul+heading+hashtag
// membuat notifikasi push jadi 3x lipat panjang & terasa dobel.
test("sanitizeCaption: buang baris heading '# ...' di awal + baris kosong sesudahnya", () => {
  const raw =
    "# 🐱 Upgrade Waktu Makan Si Meong dengan Kombinasi Sempurna! 🐟✨\n\nDry food saja sudah enak, tapi kenapa tidak dibuat lebih spesial?";
  const result = sanitizeCaption(raw);
  assert.equal(
    result,
    "Dry food saja sudah enak, tapi kenapa tidak dibuat lebih spesial?",
  );
});

test("sanitizeCaption: hashtag asli (tanpa spasi setelah #) dibatasi maks 3", () => {
  const raw =
    "Dry food saja sudah enak, tapi kenapa tidak dibuat lebih spesial? #Majes #MajesMagicBites #MajesNutriTopper #FoodTopper #CatTreat #DryFood #MakananKucing #SnackKucing #CatLover #CatLife #CatIndonesia #PetLovers #NataloPetshop";
  const result = sanitizeCaption(raw);
  const hashtags = result.match(/#[\p{L}\p{N}_]+/gu) ?? [];
  assert.equal(hashtags.length, 3);
  assert.deepEqual(hashtags, ["#Majes", "#MajesMagicBites", "#MajesNutriTopper"]);
});

test("sanitizeCaption: caption normal (tanpa heading, ≤3 hashtag) tidak berubah", () => {
  const raw = "Yuk cek video groomingnya! 🐾 #NataloPetshop";
  assert.equal(sanitizeCaption(raw), raw);
});

test("sanitizeCaption: '#' di tengah kalimat (BUKAN heading di awal) tidak dibuang", () => {
  const raw = "Promo #1 minggu ini cuma di Natalo! 🎉";
  assert.equal(sanitizeCaption(raw), raw);
});

test("sanitizeCaption: kombinasi heading DAN hashtag berlebih sekaligus dibersihkan", () => {
  const raw =
    "# Judul yang diulang lagi\n\nCaption asli di sini.\n\n#a #b #c #d #e";
  const result = sanitizeCaption(raw);
  assert.ok(!result.startsWith("#"));
  assert.ok(result.includes("Caption asli di sini."));
  const hashtags = result.match(/#[\p{L}\p{N}_]+/gu) ?? [];
  assert.equal(hashtags.length, 3);
});
