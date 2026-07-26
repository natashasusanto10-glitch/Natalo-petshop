import test from "node:test";
import assert from "node:assert/strict";
import {
  PET_SPECIES,
  SPECIES_CATEGORIES,
  WIB_OFFSET_MINUTES,
  allowedCategoriesFor,
  candidateGroup,
  dailySeed,
  fnv1a32,
  interleaveGroups,
  rotateFrom,
  selectSuggestionIds,
  speciesAllows,
  wibDateKey,
} from "../lib/pet-shopping";

const c = (
  id: string,
  categoryName: string | null,
  targetSpecies: string[] = [],
) => ({ id, categoryName, targetSpecies });

test("PET_SPECIES hanya 5 spesies yang benar-benar dipakai", () => {
  assert.deepEqual(
    [...PET_SPECIES],
    ["Kucing", "Anjing", "Hamster", "Kelinci", "Ikan"],
  );
  assert.equal(PET_SPECIES.includes("Burung"), false);
  assert.equal(PET_SPECIES.includes("Reptil"), false);
});

test("allowlist kategori per spesies sesuai katalog produksi", () => {
  assert.deepEqual([...allowedCategoriesFor("Anjing")], [
    "Makanan Anjing",
    "Snack Anjing",
  ]);
  assert.deepEqual([...allowedCategoriesFor("Kucing")], [
    "Makanan Kucing",
    "Snack Kucing",
    "Pasir Kucing",
  ]);
  assert.deepEqual([...allowedCategoriesFor("Ikan")], [
    "Makanan Ikan",
    "Obat Ikan",
  ]);
});

test("Hamster & Kelinci dipetakan ke kategori Hewan Kecil", () => {
  const expected = ["Makanan Hewan Kecil", "Perlengkapan Hewan Kecil"];
  assert.deepEqual([...allowedCategoriesFor("Hamster")], expected);
  assert.deepEqual([...allowedCategoriesFor("Kelinci")], expected);
});

test("spesies tak dikenal (data lama 'Burung') = tanpa kategori apa pun", () => {
  assert.deepEqual([...allowedCategoriesFor("Burung")], []);
  assert.equal(speciesAllows(c("p1", "Makanan Anjing"), "Burung"), false);
});

test("kategori di allowlist = boleh", () => {
  assert.equal(speciesAllows(c("p1", "Makanan Anjing"), "Anjing"), true);
  assert.equal(speciesAllows(c("p2", "Snack Anjing"), "Anjing"), true);
});

test("kategori di luar allowlist = ditolak (netral pun ditolak)", () => {
  assert.equal(speciesAllows(c("p1", "Grooming Tools"), "Anjing"), false);
  assert.equal(speciesAllows(c("p2", "Peralatan Aquarium"), "Anjing"), false);
  assert.equal(speciesAllows(c("p3", "Obat & Suplemen"), "Anjing"), false);
  assert.equal(speciesAllows(c("p4", null), "Anjing"), false);
});

test("kategori spesies LAIN ditolak tanpa perlu blacklist", () => {
  assert.equal(speciesAllows(c("p1", "Makanan Kucing"), "Anjing"), false);
  assert.equal(speciesAllows(c("p2", "Makanan Reptil"), "Anjing"), false);
});

test("targetSpecies cocok menang mutlak walau kategori di luar allowlist", () => {
  assert.equal(
    speciesAllows(c("p1", "Obat & Suplemen", ["Anjing"]), "Anjing"),
    true,
  );
});

test("targetSpecies terisi tapi spesies lain = ditolak walau kategori cocok", () => {
  assert.equal(
    speciesAllows(c("p1", "Makanan Anjing", ["Kucing"]), "Anjing"),
    false,
  );
});

test("pencocokan kategori peka nama persis, bukan substring", () => {
  // "Makanan Anjing Premium" BUKAN kategori yang ada di katalog; exact match
  // mencegah kategori baru bocor tanpa keputusan manusia.
  assert.equal(
    speciesAllows(c("p1", "Makanan Anjing Premium"), "Anjing"),
    false,
  );
});

test("candidateGroup: lolos via targetSpecies → 'target', lewat kategori → nama kategori", () => {
  assert.equal(
    candidateGroup(c("p1", "Obat & Suplemen", ["Anjing"]), "Anjing"),
    "target",
  );
  assert.equal(
    candidateGroup(c("p2", "Snack Anjing"), "Anjing"),
    "Snack Anjing",
  );
});

test("SPECIES_CATEGORIES punya entri untuk setiap PET_SPECIES", () => {
  for (const s of PET_SPECIES) {
    assert.ok(
      SPECIES_CATEGORIES[s] && SPECIES_CATEGORIES[s].length > 0,
      `spesies ${s} wajib punya kategori`,
    );
  }
});

test("WIB_OFFSET_MINUTES = 420 (UTC+7)", () => {
  assert.equal(WIB_OFFSET_MINUTES, 420);
});

test("wibDateKey: tengah hari UTC → tanggal WIB yang sama", () => {
  assert.equal(wibDateKey(new Date("2026-07-26T05:00:00Z")), "2026-07-26");
});

test("wibDateKey: 16:59Z masih 26 Juli WIB, 17:01Z sudah 27 Juli WIB", () => {
  // Ini alasan seed TIDAK boleh pakai tanggal UTC: kalau UTC, isi grid
  // berganti jam 07.00 WIB — di tengah pagi user, terasa acak.
  assert.equal(wibDateKey(new Date("2026-07-26T16:59:00Z")), "2026-07-26");
  assert.equal(wibDateKey(new Date("2026-07-26T17:01:00Z")), "2026-07-27");
});

test("wibDateKey: tepat tengah malam WIB masuk hari baru", () => {
  assert.equal(wibDateKey(new Date("2026-07-26T17:00:00Z")), "2026-07-27");
});

test("wibDateKey: bulan & hari selalu 2 digit", () => {
  assert.equal(wibDateKey(new Date("2026-01-05T05:00:00Z")), "2026-01-05");
});

test("fnv1a32: deterministik, unsigned, berbeda untuk input berbeda", () => {
  assert.equal(fnv1a32("abc"), fnv1a32("abc"));
  assert.notEqual(fnv1a32("abc"), fnv1a32("abd"));
  assert.ok(fnv1a32("pet-1:2026-07-26") >= 0);
  assert.ok(Number.isInteger(fnv1a32("pet-1:2026-07-26")));
});

test("dailySeed: sama dalam satu hari WIB, beda antar hari", () => {
  const pagi = new Date("2026-07-26T01:00:00Z"); // 08:00 WIB
  const malam = new Date("2026-07-26T15:00:00Z"); // 22:00 WIB
  const besok = new Date("2026-07-27T01:00:00Z");
  assert.equal(dailySeed("pet-1", pagi), dailySeed("pet-1", malam));
  assert.notEqual(dailySeed("pet-1", pagi), dailySeed("pet-1", besok));
});

test("dailySeed: pet berbeda dapat seed berbeda di hari yang sama", () => {
  const now = new Date("2026-07-26T05:00:00Z");
  assert.notEqual(dailySeed("pet-1", now), dailySeed("pet-2", now));
});

test("rotateFrom: rotasi kiri dengan wrap-around", () => {
  assert.deepEqual(rotateFrom([1, 2, 3, 4, 5], 2), [3, 4, 5, 1, 2]);
  assert.deepEqual(rotateFrom([1, 2, 3], 0), [1, 2, 3]);
});

test("rotateFrom: offset lebih besar dari panjang di-modulo", () => {
  assert.deepEqual(rotateFrom([1, 2, 3], 7), [2, 3, 1]);
});

test("rotateFrom: array kosong tidak melempar (tak ada pembagian nol)", () => {
  assert.deepEqual(rotateFrom([], 5), []);
});

test("rotateFrom: tidak memutasi input", () => {
  const input = [1, 2, 3];
  rotateFrom(input, 1);
  assert.deepEqual(input, [1, 2, 3]);
});

test("interleaveGroups: round-robin, tak pernah dua slot berurutan satu grup", () => {
  const out = interleaveGroups([["a1", "a2", "a3"], ["b1", "b2"]], 5);
  assert.deepEqual(out, ["a1", "b1", "a2", "b2", "a3"]);
});

test("interleaveGroups: grup habis dilewati, grup besar mengisi sisa", () => {
  const out = interleaveGroups([["a1", "a2", "a3", "a4"], ["b1"]], 5);
  assert.deepEqual(out, ["a1", "b1", "a2", "a3", "a4"]);
});

test("interleaveGroups: berhenti di limit", () => {
  const out = interleaveGroups([["a1", "a2", "a3"], ["b1", "b2", "b3"]], 3);
  assert.deepEqual(out, ["a1", "b1", "a2"]);
});

test("interleaveGroups: total lebih kecil dari limit → keluarkan semua", () => {
  const out = interleaveGroups([["a1"], ["b1"]], 12);
  assert.deepEqual(out, ["a1", "b1"]);
});

test("interleaveGroups: tanpa grup → kosong", () => {
  assert.deepEqual(interleaveGroups([], 12), []);
});

// ── selectSuggestionIds ──────────────────────────────────────────────

const NOW = new Date("2026-07-26T05:00:00Z");

/** Kandidat sintetis: n produk di satu kategori, id `{prefix}{i}`. */
const many = (prefix: string, categoryName: string, n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `${prefix}${i}`,
    categoryName,
    targetSpecies: [] as string[],
  }));

test("selectSuggestionIds: menjalin kategori, bukan blok satu kategori", () => {
  const out = selectSuggestionIds(
    [...many("m", "Makanan Anjing", 20), ...many("s", "Snack Anjing", 20)],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.equal(out.length, 12);
  // Tak ada dua slot berurutan dari kategori yang sama (m vs s).
  for (let i = 1; i < out.length; i++) {
    assert.notEqual(
      out[i][0],
      out[i - 1][0],
      `slot ${i} dan ${i - 1} dari kategori yang sama: ${out.join(",")}`,
    );
  }
});

test("selectSuggestionIds: kategori kecil tetap kebagian slot", () => {
  // Realita katalog Anjing: 234 makanan vs 21 snack. Tanpa penjalinan,
  // makanan menelan seluruh grid — inilah keluhan 'monoton'.
  const out = selectSuggestionIds(
    [...many("m", "Makanan Anjing", 234), ...many("s", "Snack Anjing", 21)],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.ok(
    out.filter((id) => id.startsWith("s")).length >= 5,
    `snack terlalu sedikit: ${out.join(",")}`,
  );
});

test("selectSuggestionIds: grup 'target' dapat slot pertama", () => {
  const out = selectSuggestionIds(
    [
      ...many("m", "Makanan Anjing", 10),
      { id: "tagged", categoryName: "Obat & Suplemen", targetSpecies: ["Anjing"] },
    ],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.equal(out[0], "tagged");
});

test("selectSuggestionIds: produk spesies lain & netral dibuang", () => {
  const out = selectSuggestionIds(
    [
      { id: "cat", categoryName: "Makanan Kucing", targetSpecies: [] },
      { id: "aqua", categoryName: "Peralatan Aquarium", targetSpecies: [] },
      { id: "groom", categoryName: "Grooming Tools", targetSpecies: [] },
      { id: "dog", categoryName: "Makanan Anjing", targetSpecies: [] },
    ],
    { petType: "Anjing", petId: "pet-1", now: NOW, limit: 12 },
  );
  assert.deepEqual(out, ["dog"]);
});

test("selectSuggestionIds: deterministik dalam satu hari WIB", () => {
  const cands = [
    ...many("m", "Makanan Anjing", 50),
    ...many("s", "Snack Anjing", 10),
  ];
  const pagi = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-26T01:00:00Z"),
    limit: 12,
  });
  const malam = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-26T15:00:00Z"),
    limit: 12,
  });
  assert.deepEqual(pagi, malam, "rail & grid dalam sehari WAJIB sama");
});

test("selectSuggestionIds: hari berbeda → isi berputar", () => {
  const cands = [
    ...many("m", "Makanan Anjing", 50),
    ...many("s", "Snack Anjing", 10),
  ];
  const hariIni = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-26T05:00:00Z"),
    limit: 12,
  });
  const besok = selectSuggestionIds(cands, {
    petType: "Anjing",
    petId: "pet-1",
    now: new Date("2026-07-27T05:00:00Z"),
    limit: 12,
  });
  assert.notDeepEqual(hariIni, besok);
});

test("selectSuggestionIds: 6 pertama = prefix dari 12 (janji rail=prefix grid)", () => {
  const cands = [
    ...many("m", "Makanan Anjing", 50),
    ...many("s", "Snack Anjing", 10),
  ];
  const opts = { petType: "Anjing", petId: "pet-1", now: NOW };
  const dua_belas = selectSuggestionIds(cands, { ...opts, limit: 12 });
  const enam = selectSuggestionIds(cands, { ...opts, limit: 6 });
  assert.deepEqual(enam, dua_belas.slice(0, 6));
});

test("selectSuggestionIds: pool kecil (Hamster 7 produk) tidak dipaksa 12", () => {
  const out = selectSuggestionIds(
    [
      ...many("f", "Makanan Hewan Kecil", 6),
      ...many("p", "Perlengkapan Hewan Kecil", 1),
    ],
    { petType: "Hamster", petId: "pet-9", now: NOW, limit: 12 },
  );
  assert.equal(out.length, 7);
});

test("selectSuggestionIds: kandidat kosong → kosong", () => {
  assert.deepEqual(
    selectSuggestionIds([], {
      petType: "Anjing",
      petId: "pet-1",
      now: NOW,
      limit: 12,
    }),
    [],
  );
});
