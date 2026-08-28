import { test } from "node:test";
import assert from "node:assert/strict";

import {
  bunnyTusFingerprint,
  isVideoFileReadable,
  shouldResumePreviousUpload,
  VIDEO_FILE_MISSING_MESSAGE,
} from "../lib/feed/tus-upload";

const FILE = {
  name: "id-11110105-6vg6o.mp4",
  type: "video/mp4",
  size: 6_900_000,
  lastModified: 1_756_000_000_000,
};

test("file yang sama dengan videoId berbeda TIDAK berbagi fingerprint", () => {
  // Regresi: fingerprint default tus-js-client hanya memuat nama file +
  // endpoint, sedangkan endpoint Bunny selalu sama. Percobaan upload kedua
  // (videoId baru) jadi me-resume URL video lama yang sudah mati → PATCH
  // chunk offset 0 ditolak tanpa header CORS ("response code: n/a").
  const a = bunnyTusFingerprint("9726430f4b404e068739bf37724494fb", FILE);
  const b = bunnyTusFingerprint("aaaa1111bbbb2222cccc3333dddd4444", FILE);
  assert.notEqual(a, b);
});

test("file & videoId sama tetap menghasilkan fingerprint sama (resume asli tetap jalan)", () => {
  const id = "9726430f4b404e068739bf37724494fb";
  assert.equal(bunnyTusFingerprint(id, FILE), bunnyTusFingerprint(id, FILE));
});

test("blob hasil trim tanpa nama tidak bikin fingerprint meledak", () => {
  const id = "9726430f4b404e068739bf37724494fb";
  assert.equal(typeof bunnyTusFingerprint(id, {}), "string");
  assert.notEqual(bunnyTusFingerprint(id, {}), bunnyTusFingerprint("lain", {}));
});

test("resume ditolak kalau URL simpanan milik video lain", () => {
  const stale = "https://video.bunnycdn.com/tusupload/9726430f4b404e068739bf37724494fb";
  assert.equal(shouldResumePreviousUpload(stale, "aaaa1111bbbb2222cccc3333dddd4444"), false);
});

test("resume diterima kalau URL simpanan milik videoId yang sedang dipakai", () => {
  const id = "9726430f4b404e068739bf37724494fb";
  assert.equal(
    shouldResumePreviousUpload(`https://video.bunnycdn.com/tusupload/${id}`, id),
    true,
  );
});

test("URL kosong / videoId kosong tidak pernah di-resume", () => {
  assert.equal(shouldResumePreviousUpload(null, "abc"), false);
  assert.equal(shouldResumePreviousUpload(undefined, "abc"), false);
  assert.equal(shouldResumePreviousUpload("", "abc"), false);
  assert.equal(shouldResumePreviousUpload("https://video.bunnycdn.com/tusupload/x", ""), false);
});

test("berkas yang masih ada dianggap terbaca", async () => {
  const blob = new Blob([new Uint8Array([1, 2, 3])], { type: "video/mp4" });
  assert.equal(await isVideoFileReadable(blob), true);
});

test("berkas kosong tetap dianggap terbaca (bukan kasus hilang)", async () => {
  assert.equal(await isVideoFileReadable(new Blob([])), true);
});

test("berkas yang lenyap dari disk dilaporkan tidak terbaca", async () => {
  // Browser melempar NotFoundError saat File menunjuk berkas yang sudah
  // dipindah/dihapus — inilah yang tadinya muncul sebagai ProgressEvent
  // tanpa status HTTP.
  const dangling = {
    slice: () => ({
      arrayBuffer: async () => {
        throw new DOMException("A requested file could not be found", "NotFoundError");
      },
    }),
  } as unknown as Blob;
  assert.equal(await isVideoFileReadable(dangling), false);
});

test("pesan berkas hilang menyebut aksi yang harus diambil admin", () => {
  assert.match(VIDEO_FILE_MISSING_MESSAGE, /Pilih ulang/i);
  assert.doesNotMatch(VIDEO_FILE_MISSING_MESSAGE, /tus|ProgressEvent|PATCH/i);
});
