import { test } from "node:test";
import assert from "node:assert/strict";

import { paginationRange, type PageSlot } from "../lib/admin/pagination-range";

const nums = (slots: PageSlot[]) => slots.filter((s): s is number => s !== "gap");

test("halaman sedikit ditampilkan semua, tanpa titik-titik", () => {
  assert.deepEqual(paginationRange(1, 1), [1]);
  assert.deepEqual(paginationRange(2, 5), [1, 2, 3, 4, 5]);
  assert.deepEqual(paginationRange(4, 7), [1, 2, 3, 4, 5, 6, 7]);
});

test("di awal daftar panjang: nomor rapat di kiri, satu lompatan ke halaman akhir", () => {
  assert.deepEqual(paginationRange(1, 29), [1, 2, 3, 4, 5, "gap", 29]);
  assert.deepEqual(paginationRange(3, 29), [1, 2, 3, 4, 5, "gap", 29]);
});

test("di tengah: halaman aktif diapit tetangganya, lompatan di kedua sisi", () => {
  assert.deepEqual(paginationRange(15, 29), [1, "gap", 14, 15, 16, "gap", 29]);
});

test("di akhir: deret bergeser ke kanan, TIDAK menyusut jadi dua tombol", () => {
  assert.deepEqual(paginationRange(29, 29), [1, "gap", 25, 26, 27, 28, 29]);
  assert.deepEqual(paginationRange(27, 29), [1, "gap", 25, 26, 27, 28, 29]);
});

test("lebar deret tetap saat admin mengklik berurutan — tombol tidak berpindah", () => {
  // Kalau lebarnya berubah-ubah, tombol "3" bisa berpindah ke posisi tombol
  // "4" tepat setelah diklik, dan klik berikutnya mendarat di halaman salah.
  const widths = new Set<number>();
  for (let page = 1; page <= 29; page++) {
    widths.add(paginationRange(page, 29).length);
  }
  assert.equal(widths.size, 1, `lebar berubah-ubah: ${[...widths].join(", ")}`);
});

test("halaman aktif SELALU ada di dalam deret", () => {
  for (const total of [1, 5, 8, 29, 140]) {
    for (let page = 1; page <= total; page++) {
      assert.ok(
        nums(paginationRange(page, total)).includes(page),
        `halaman ${page} dari ${total} tidak muncul`,
      );
    }
  }
});

test("nomor selalu naik dan tidak pernah kembar", () => {
  for (const total of [6, 9, 29, 140]) {
    for (let page = 1; page <= total; page++) {
      const list = nums(paginationRange(page, total));
      for (let i = 1; i < list.length; i++) {
        assert.ok(list[i] > list[i - 1], `urutan rusak di ${page}/${total}`);
      }
    }
  }
});

test("halaman pertama dan terakhir selalu bisa dijangkau satu klik", () => {
  for (const total of [6, 29, 140]) {
    for (const page of [1, 2, Math.ceil(total / 2), total - 1, total]) {
      const list = nums(paginationRange(page, total));
      assert.equal(list[0], 1);
      assert.equal(list.at(-1), total);
    }
  }
});

test("masukan tak masuk akal tidak melahirkan deret rusak", () => {
  assert.deepEqual(paginationRange(1, 0), []);
  assert.deepEqual(paginationRange(5, -3), []);
  assert.deepEqual(paginationRange(Number.NaN, 5), [1, 2, 3, 4, 5]);
  // Halaman melewati batas dijepit ke halaman terakhir, bukan bikin deret liar.
  assert.deepEqual(paginationRange(999, 29), [1, "gap", 25, 26, 27, 28, 29]);
});

test("siblings 0 tetap menampilkan halaman aktif", () => {
  const list = paginationRange(15, 29, 0);
  assert.ok(nums(list).includes(15));
});

test('"…" tidak pernah menyembunyikan hanya SATU halaman', () => {
  // Regresi nyata: pada halaman 4 dari 29 dulu muncul "1 … 3 4 5 … 29" —
  // titik-titiknya hanya menutupi halaman 2, memakan tempat yang sama dengan
  // angkanya sambil menghilangkan satu tujuan yang bisa diklik. Aturan umum
  // ini menjaga kedua ujung sekaligus, bukan cuma dua kasus yang kebetulan
  // kuperiksa.
  for (const total of [7, 8, 9, 10, 12, 29, 140]) {
    for (let page = 1; page <= total; page++) {
      const slots = paginationRange(page, total);
      for (let i = 0; i < slots.length; i++) {
        if (slots[i] !== "gap") continue;
        const before = slots[i - 1];
        const after = slots[i + 1];
        assert.equal(typeof before, "number", `gap di tepi kiri (${page}/${total})`);
        assert.equal(typeof after, "number", `gap di tepi kanan (${page}/${total})`);
        const hidden = (after as number) - (before as number) - 1;
        assert.ok(
          hidden >= 2,
          `gap cuma menyembunyikan ${hidden} halaman di ${page}/${total}: ${JSON.stringify(slots)}`,
        );
      }
    }
  }
});

test("batas tempat bug itu bersembunyi: halaman 4 dan halaman ke-4-dari-belakang", () => {
  assert.deepEqual(paginationRange(4, 29), [1, 2, 3, 4, 5, "gap", 29]);
  assert.deepEqual(paginationRange(26, 29), [1, "gap", 25, 26, 27, 28, 29]);
});

test("lebar deret tetap — diperiksa untuk banyak total, bukan hanya 29", () => {
  for (const total of [8, 9, 10, 12, 29, 140]) {
    const widths = new Set<number>();
    for (let page = 1; page <= total; page++) {
      widths.add(paginationRange(page, total).length);
    }
    assert.equal(widths.size, 1, `total ${total}: lebar berubah (${[...widths].join(", ")})`);
  }
});
