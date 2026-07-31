# PR3 — Perbaikan Bloker Batas-2000 pada Sort Berbasis Penjualan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hilangkan mode-gagal "best-seller lama hilang diam-diam" di `searchProductsFromDb`, supaya halaman `/products` aman dipindahkan ke stack search di PR4.

**Architecture:** Untuk sort berbasis penjualan (`best_seller`, `trending`), ranking dijalankan **lebih dulu**, lalu produk diambil dalam dua bagian: **kepala** (produk yang pernah terjual, diambil lewat `id IN rankedIds` — jadi tak pernah terpotong batas "terbaru dulu") dan **ekor** (belum pernah terjual, `createdAt desc`, dibatasi kuota). Keduanya digabung lalu diurutkan seperti sekarang. Logika pengurutannya diekstrak jadi fungsi murni yang bisa diuji, supaya invarian "produk belum terjual TIDAK dibuang" punya tes eksplisit.

**Tech Stack:** Next.js (App Router), Prisma, TypeScript, `node:test` via `tsx`.

## Global Constraints

- **PR3 hanya menyentuh backend search.** TIDAK ada perubahan pada `app/products/**`, `app/search/page.tsx`, `components/**`, `flutter_app/**`, `prisma/schema.prisma`, atau logika cart/checkout/voucher/loyalty/auth. Migrasi halaman `/products` adalah PR4.
- **Read-only additif.** Tidak ada endpoint baru, tidak ada perubahan schema, tidak ada operasi tulis.
- **Regresi nol yang bisa dibuktikan.** Katalog Preview saat ini **1324 produk aktif**, jauh di bawah batas 2000 — maka hasil `/api/search` untuk semua sort **wajib identik byte-per-byte** sebelum vs sesudah perubahan. Perbedaan apa pun = bug, bukan "perbaikan".
- **Perilaku yang WAJIB dipertahankan:** produk yang belum pernah terjual **tidak boleh dibuang** dari hasil — didorong ke ekor lalu diurut dengan `compareSearchItems` (lihat komentar Indonesia yang sudah ada di `searchProductsFromDb`). Ini beda disengaja dari `/api/products` yang menggabung filter+sort dalam satu param `popular`.
- **Jangan gagal diam-diam.** `console.warn` saat kuota pengambilan tersentuh harus tetap ada dan akurat (tidak boleh false-positive).
- **Jangan sentuh kode mati.** `buildDbProductWhere` (`lib/search.ts:294–324`) dan `buildDbSearchPageArgs` (`lib/search.ts:326–348`) tidak dipakai jalur ini — biarkan apa adanya.
- **Jalur Meilisearch tidak diubah.** Meili sedang OFF; `best_seller`/`trending` di Meili memakai proksi berbeda dan sudah ada guard-nya. Di luar cakupan.
- **Konvensi tes repo:** helper murni diuji dengan `node:test` (`npx tsx --test tests/search.test.ts`); komponen React tidak punya unit test. Ikuti itu — jangan pasang test runner baru.
- Commit tiap task selesai, pesan gaya conventional-commit.

---

## File Structure

**Modified:**
- `lib/search.ts` — ekstrak `orderDocsBySalesRank` (fungsi murni, diekspor untuk diuji); jalankan ranking sebelum pengambilan; ganti satu `findMany` jadi kepala+ekor; dua konstanta kuota bernama; perbaiki kondisi `console.warn`.
- `tests/search.test.ts` — tes unit untuk `orderDocsBySalesRank` (pakai helper `doc()` yang sudah ada di file itu).

Tidak ada file baru.

---

## Task 1: Ekstrak `orderDocsBySalesRank` (murni, TDD, tanpa ubah perilaku)

**Files:**
- Modify: `lib/search.ts` (blok ranking ~879–888 dan cabang sort ~898–909)
- Test: `tests/search.test.ts`

**Interfaces:**
- Consumes: `ProductSearchDoc` (sudah diekspor dari `lib/search.ts`), `compareSearchItems` (privat di file yang sama).
- Produces:
  ```ts
  export function orderDocsBySalesRank(
    docs: ProductSearchDoc[],
    rankedIds: string[],
    tiebreak: (a: ProductSearchDoc, b: ProductSearchDoc) => number,
  ): ProductSearchDoc[]
  ```
  Dipakai Task 2 (call site-nya tidak berubah lagi setelah task ini).

- [ ] **Step 1: Tulis tes yang gagal**

Buka `tests/search.test.ts`. Tambahkan `orderDocsBySalesRank` ke blok import yang sudah ada dari `@/lib/search` (yang sekarang mengimpor `filterSortPaginateSearchDocs`, `type ProductSearchDoc`, `type SearchOptions`), sehingga menjadi:

```ts
import {
  filterSortPaginateSearchDocs,
  orderDocsBySalesRank,
  type ProductSearchDoc,
  type SearchOptions,
} from "@/lib/search";
```

Lalu tambahkan empat tes ini di akhir file (helper `doc()` sudah tersedia di file ini — pakai, jangan bikin baru):

```ts
test("sales rank ordering keeps never-sold products instead of dropping them", () => {
  const sold = doc({ id: "sold", slug: "sold", name: "Pernah terjual" });
  const unsold = doc({ id: "unsold", slug: "unsold", name: "Belum pernah terjual" });

  const ordered = orderDocsBySalesRank([unsold, sold], ["sold"], () => 0);

  assert.deepEqual(
    ordered.map((item) => item.id),
    ["sold", "unsold"],
  );
});

test("sales rank ordering follows ranked id order, not input order", () => {
  const a = doc({ id: "a", slug: "a" });
  const b = doc({ id: "b", slug: "b" });
  const c = doc({ id: "c", slug: "c" });

  const ordered = orderDocsBySalesRank([a, b, c], ["c", "a", "b"], () => 0);

  assert.deepEqual(
    ordered.map((item) => item.id),
    ["c", "a", "b"],
  );
});

test("never-sold products fall back to the tiebreak comparator", () => {
  const cheap = doc({ id: "cheap", slug: "cheap", price_min: 10_000 });
  const pricey = doc({ id: "pricey", slug: "pricey", price_min: 90_000 });

  const ordered = orderDocsBySalesRank(
    [pricey, cheap],
    [],
    (a, b) => a.price_min - b.price_min,
  );

  assert.deepEqual(
    ordered.map((item) => item.id),
    ["cheap", "pricey"],
  );
});

test("sales rank ordering does not mutate the caller's array", () => {
  const a = doc({ id: "a", slug: "a" });
  const b = doc({ id: "b", slug: "b" });
  const input = [a, b];

  orderDocsBySalesRank(input, ["b"], () => 0);

  assert.deepEqual(
    input.map((item) => item.id),
    ["a", "b"],
  );
});
```

- [ ] **Step 2: Jalankan tes, pastikan GAGAL**

Run: `npx tsx --test tests/search.test.ts`
Expected: FAIL — `orderDocsBySalesRank` belum diekspor (error kompilasi/impor).

- [ ] **Step 3: Tambahkan fungsi murni di `lib/search.ts`**

Sisipkan tepat SETELAH fungsi `compareSearchItems` berakhir (baris `}` di `lib/search.ts:699`) dan SEBELUM `export function filterSortPaginateSearchDocs` (baris 701):

```ts

/**
 * Urutkan dokumen memakai urutan ranking penjualan (`rankedIds`, indeks 0 =
 * paling laku).
 *
 * Produk yang TIDAK ada di `rankedIds` (belum pernah terjual) sengaja TIDAK
 * dibuang — didorong ke ekor lalu diurut dengan `tiebreak`. Sort tidak boleh
 * menghilangkan hasil (beda dengan /api/products yang menggabung filter+sort
 * dalam satu param `popular`).
 */
export function orderDocsBySalesRank(
  docs: ProductSearchDoc[],
  rankedIds: string[],
  tiebreak: (a: ProductSearchDoc, b: ProductSearchDoc) => number,
): ProductSearchDoc[] {
  const rank = new Map(rankedIds.map((id, index) => [id, index]));
  return [...docs].sort((a, b) => {
    const rankA = rank.get(a.id) ?? Infinity;
    const rankB = rank.get(b.id) ?? Infinity;
    if (rankA !== rankB) return rankA - rankB;
    return tiebreak(a, b);
  });
}
```

- [ ] **Step 4: Jalankan tes, pastikan LULUS**

Run: `npx tsx --test tests/search.test.ts`
Expected: PASS — semua tes lama tetap hijau + 4 tes baru lulus.

- [ ] **Step 5: Pakai fungsi itu di `searchProductsFromDb` (perilaku tetap sama)**

Di `lib/search.ts`, ganti blok ranking ini (sekarang di baris 879–888):

```ts
  let salesRank: Map<string, number> | null = null;
  if (opts.sort === "best_seller" || opts.sort === "trending") {
    const rankedIds =
      opts.sort === "trending"
        ? await getTrendingProductIds({ productWhere: where })
        : await getBestSellerProductIds({ productWhere: where });
    if (rankedIds.length > 0) {
      salesRank = new Map(rankedIds.map((id, index) => [id, index]));
    }
  }
```

menjadi:

```ts
  let rankedIds: string[] = [];
  if (opts.sort === "best_seller" || opts.sort === "trending") {
    rankedIds =
      opts.sort === "trending"
        ? await getTrendingProductIds({ productWhere: where })
        : await getBestSellerProductIds({ productWhere: where });
  }
```

Lalu ganti cabang sort ini (sekarang di baris 898–909):

```ts
  } else if (salesRank) {
    const rank = salesRank;
    const tiebreak = compareSearchItems(opts.sort, q);
    // Produk tanpa penjualan TIDAK dibuang — didorong ke ekor. Sort tidak
    // boleh menghilangkan hasil (beda dengan /api/products yang menggabung
    // filter+sort dalam satu param `popular`).
    items = [...docs].sort((a, b) => {
      const rankA = rank.get(a.id) ?? Infinity;
      const rankB = rank.get(b.id) ?? Infinity;
      if (rankA !== rankB) return rankA - rankB;
      return tiebreak(a, b);
    });
  } else {
```

menjadi:

```ts
  } else if (rankedIds.length > 0) {
    items = orderDocsBySalesRank(docs, rankedIds, compareSearchItems(opts.sort, q));
  } else {
```

- [ ] **Step 6: Typecheck + lint + tes**

Run: `npx tsc --noEmit`
Expected: tidak ada error BARU. Repo ini punya 2 error lama yang tidak berhubungan di `app/api/admin/reset-all/route.ts` (`chatMessage`/`chatThread` tidak ada di PrismaClient) — abaikan, jangan diperbaiki.

Run: `npm run lint`
Expected: 0 errors (warning lama di file lain wajar).

Run: `npm test`
Expected: semua hijau.

- [ ] **Step 7: Commit**

```bash
git add lib/search.ts tests/search.test.ts
git commit -m "refactor(search): ekstrak orderDocsBySalesRank + tes invarian produk belum terjual"
```

---

## Task 2: Ambil kepala terurut-penjualan lewat ranked-ids (perbaikan bloker)

**Files:**
- Modify: `lib/search.ts` (konstanta baru + blok pengambilan produk di `searchProductsFromDb`)

**Interfaces:**
- Consumes: `orderDocsBySalesRank` (Task 1); `getBestSellerProductIds`/`getTrendingProductIds` dari `@/lib/product-ranking` (sudah diimpor di file ini) — keduanya menerima `{ productWhere, take?, skip? }` dan mengembalikan `string[]` (id produk, terurut, paling laku dulu); `getProductSearchInclude()`.
- Produces: dua konstanta modul `CATALOG_FETCH_CAP` dan `SALES_HEAD_CAP` (keduanya `2000`). Tidak ada API publik baru.

- [ ] **Step 1: Rekam baseline SEBELUM mengubah kode**

Ini bukti regresi-nol. Katalog Preview (1324 produk) ada di bawah batas 2000, jadi keluaran WAJIB identik sesudah perubahan.

Pastikan dev server worktree ini jalan di `http://localhost:3022`. Kalau belum, jalankan lewat Browser preview tool: `preview_start` dengan `{"name": "listing-pr2-filters"}` (entri itu sudah menunjuk ke direktori worktree ini; kalau sudah jalan ia akan melaporkan `reused: true`). Jangan pakai Bash untuk menjalankan dev server.

Lalu rekam baseline lewat Bash:

```bash
mkdir -p /tmp/pr3
for s in best_seller trending newest rating_desc price_asc price_desc relevance; do
  curl -s "http://localhost:3022/api/search?sort=$s&per_page=24" \
    | python -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({'sort':'$s','total':d['total'],'ids':[i['id'] for i in d['items']]}, indent=1))" \
    > "/tmp/pr3/before-$s.json"
done
cat /tmp/pr3/before-best_seller.json
```

Expected: tiap file berisi `total` dan daftar `ids`. Catat `total` untuk `best_seller` di laporanmu. Kalau `curl` mengembalikan error/kosong, JANGAN lanjut — laporkan BLOCKED (server atau DB belum siap).

- [ ] **Step 2: Tambahkan dua konstanta kuota bernama**

Di `lib/search.ts`, sisipkan tepat SEBELUM baris `async function searchProductsFromDb(opts: NormalizedSearchOptions) {` (sekarang baris 786):

```ts
/**
 * Batas baris yang diambil untuk satu permintaan search TANPA kata kunci.
 * Hanya membatasi ekor (produk yang belum pernah terjual) — kepala yang
 * terurut-penjualan diambil lewat id-nya sendiri, jadi tidak pernah terpotong.
 */
const CATALOG_FETCH_CAP = 2000;

/**
 * Batas panjang kepala terurut-penjualan. Produk dengan peringkat di bawah ini
 * jatuh ke ekor — aman, karena tidak ada pembeli yang membuka halaman sejauh
 * itu, dan batas ini menjaga ukuran klausa `IN`/`NOT IN` tetap waras.
 */
const SALES_HEAD_CAP = 2000;

```

- [ ] **Step 3: Jalankan ranking SEBELUM pengambilan, dan batasi kepalanya**

Blok `rankedIds` (hasil Task 1) saat ini berada SESUDAH pengambilan produk. Pindahkan ke ATAS.

Pertama, HAPUS blok ini dari posisinya sekarang (ada di antara pembuatan `docs` dan cabang sort):

```ts
  let rankedIds: string[] = [];
  if (opts.sort === "best_seller" || opts.sort === "trending") {
    rankedIds =
      opts.sort === "trending"
        ? await getTrendingProductIds({ productWhere: where })
        : await getBestSellerProductIds({ productWhere: where });
  }
```

Termasuk komentar tiga baris tepat di atasnya:

```ts
  // best_seller & trending di-rank dari data penjualan asli (OrderItem),
  // bukan proksi review_count. Pakai `where` yang sama supaya ranking
  // menghormati filter aktif.
```

- [ ] **Step 4: Ganti pengambilan produk jadi kepala + ekor**

Ganti seluruh blok ini (sekarang baris 843–863, dari komentar `// NOTE: tanpa orderBy...` sampai penutup `}` dari `console.warn`):

```ts
  // NOTE: tanpa orderBy, `take: 2000` mengambil 2000 baris ARBITRER — begitu
  // katalog lewat 2000 produk, hasilnya jadi non-deterministik. Beri urutan
  // tetap (terbaru dulu) supaya potongannya stabil & bisa dijelaskan.
  const products = await prisma.product.findMany({
    where,
    include: getProductSearchInclude(),
    orderBy: [{ createdAt: "desc" }, { id: "asc" }],
    take: candidateIds ? undefined : 2000,
  });

  // Batas keras 2000 baris: begitu katalog melewatinya, potongan "terbaru dulu"
  // mulai memotong produk yang seharusnya ikut di-rank (query ranking penjualan
  // TIDAK dibatasi), sehingga best-seller lama bisa hilang diam-diam dan `total`
  // ikut terpotong. Jangan gagal diam-diam — teriak supaya ketahuan.
  if (!candidateIds && products.length >= 2000) {
    console.warn(
      `[searchProductsFromDb] Katalog mencapai batas 2000 baris (${products.length}). ` +
        "Hasil & total bisa terpotong, dan sort best_seller/trending bisa kehilangan produk lama. " +
        "Naikkan batas atau ambil produk berdasarkan ranked-ids lebih dulu.",
    );
  }
```

dengan:

```ts
  // best_seller & trending di-rank dari data penjualan asli (OrderItem), bukan
  // proksi review_count. Pakai `where` yang sama supaya ranking menghormati
  // filter aktif. Ranking dijalankan DULU supaya produk yang pernah laku bisa
  // diambil lewat id-nya di bawah.
  let rankedIds: string[] = [];
  if (opts.sort === "best_seller" || opts.sort === "trending") {
    rankedIds =
      opts.sort === "trending"
        ? await getTrendingProductIds({ productWhere: where, take: SALES_HEAD_CAP })
        : await getBestSellerProductIds({ productWhere: where, take: SALES_HEAD_CAP });
  }

  // Ambil KEPALA (pernah terjual, lewat id ranking) terpisah dari EKOR (belum
  // pernah terjual, terbaru dulu, dibatasi kuota). Tanpa pemisahan ini,
  // best-seller lama hilang diam-diam begitu katalog lewat CATALOG_FETCH_CAP:
  // query ranking menaruhnya di peringkat 1, tapi pengambilan "terbaru dulu"
  // tidak ikut membawanya sehingga produknya lenyap dari hasil.
  const useRankedHead = !candidateIds && rankedIds.length > 0;

  const rankedHeadPromise = useRankedHead
    ? prisma.product.findMany({
        where: { ...where, id: { in: rankedIds } },
        include: getProductSearchInclude(),
      })
    : null;

  // NOTE: tanpa orderBy, `take` mengambil baris ARBITRER — begitu katalog lewat
  // batas, hasilnya jadi non-deterministik. Beri urutan tetap (terbaru dulu)
  // supaya potongannya stabil & bisa dijelaskan.
  const tailPromise = prisma.product.findMany({
    where: useRankedHead ? { ...where, id: { notIn: rankedIds } } : where,
    include: getProductSearchInclude(),
    orderBy: [{ createdAt: "desc" }, { id: "asc" }],
    take: candidateIds ? undefined : CATALOG_FETCH_CAP,
  });

  const [rankedHead, tail] = await Promise.all([rankedHeadPromise, tailPromise]);
  const products = [...(rankedHead ?? []), ...tail];

  // Kepala selalu utuh; yang masih bisa terpotong hanya EKOR (produk yang belum
  // pernah terjual) — dan itu cuma terasa di halaman-halaman dalam. Jangan gagal
  // diam-diam.
  if (!candidateIds && tail.length >= CATALOG_FETCH_CAP) {
    console.warn(
      `[searchProductsFromDb] Ekor katalog menyentuh batas ${CATALOG_FETCH_CAP} baris. ` +
        "Produk yang belum pernah terjual bisa terpotong di halaman dalam, dan `total` ikut terpotong. " +
        "Naikkan CATALOG_FETCH_CAP atau pindahkan filter+paginasi ke SQL.",
    );
  }
```

- [ ] **Step 5: Typecheck + lint + tes**

Run: `npx tsc --noEmit`
Expected: tidak ada error BARU (2 error lama di `app/api/admin/reset-all/route.ts` tetap ada — abaikan).

Run: `npm run lint`
Expected: 0 errors.

Run: `npm test`
Expected: semua hijau.

- [ ] **Step 6: Buktikan regresi nol (pembanding baseline)**

Server dev memakai Fast Refresh; tunggu ~3 detik setelah edit tersimpan, lalu:

```bash
for s in best_seller trending newest rating_desc price_asc price_desc relevance; do
  curl -s "http://localhost:3022/api/search?sort=$s&per_page=24" \
    | python -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({'sort':'$s','total':d['total'],'ids':[i['id'] for i in d['items']]}, indent=1))" \
    > "/tmp/pr3/after-$s.json"
  if diff -q "/tmp/pr3/before-$s.json" "/tmp/pr3/after-$s.json" >/dev/null; then
    echo "IDENTIK: $s"
  else
    echo "BERBEDA (INVESTIGASI!): $s"; diff "/tmp/pr3/before-$s.json" "/tmp/pr3/after-$s.json" | head -20
  fi
done
```

Expected: **ketujuh sort melaporkan `IDENTIK`.** Katalog (1324) di bawah batas 2000, jadi kumpulan produk dan urutannya harus persis sama — perubahan ini hanya mengubah CARA baris diambil, bukan baris mana. Kalau ada yang `BERBEDA`, itu bug: laporkan DONE_WITH_CONCERNS beserta diff-nya, jangan dianggap wajar.

- [ ] **Step 7: Cek filter tetap dihormati oleh jalur kepala+ekor**

```bash
curl -s "http://localhost:3022/api/search?sort=best_seller&in_stock=true&per_page=5" \
  | python -c "import sys,json; d=json.load(sys.stdin); print('total', d['total']); print('semua ada stok:', all(i['total_stock']>0 for i in d['items']))"
curl -s "http://localhost:3022/api/search?sort=best_seller&min_rating=4&per_page=5" \
  | python -c "import sys,json; d=json.load(sys.stdin); print('total', d['total']); print('semua rating >=4:', all(i['avg_rating']>=4 for i in d['items']))"
```

Expected: kedua baris melaporkan `True`, dan `total` lebih kecil dari total tanpa filter. Ini membuktikan `where` masih diterapkan ke kepala DAN ekor.

- [ ] **Step 8: Commit**

```bash
git add lib/search.ts
git commit -m "fix(search): ambil kepala terurut-penjualan lewat ranked-ids, ekor terpisah

Best-seller lama bisa hilang diam-diam begitu katalog lewat 2000 produk:
query ranking tidak dibatasi, tapi pengambilan produk hanya mengambil 2000
terbaru — produk peringkat 1 yang lama tidak ikut terambil. Sekarang ranking
jalan lebih dulu, kepala diambil lewat id-nya, ekor (belum pernah terjual)
diambil terpisah dengan kuota. Warn kini menunjuk ekor supaya tidak
false-positive."
```

---

## Task 3: Verifikasi penuh + cek cakupan diff

**Files:** tidak ada (verifikasi saja)

- [ ] **Step 1: Cek statis penuh**

Run: `npx tsc --noEmit`
Expected: hanya 2 error lama di `app/api/admin/reset-all/route.ts`.

Run: `npm run lint`
Expected: 0 errors.

Run: `npm test`
Expected: semua hijau, termasuk 4 tes `orderDocsBySalesRank` dari Task 1.

Run: `npx next build`
Expected: langkah kompilasi Turbopack sukses. Build penuh akan berhenti di type-check karena 2 error lama tadi (`app/api/admin/reset-all/route.ts`) — itu memang sudah rusak sebelum branch ini dan di luar cakupan; catat, jangan perbaiki.

- [ ] **Step 2: Cek `/search` (halaman live yang memakai jalur ini) tidak rusak**

Buka `http://localhost:3022/search?q=makanan` di Browser preview tool (kalau tool browser bermasalah — sudah pernah terjadi di sesi ini — pakai `curl` sebagai gantinya dan katakan begitu di laporan).

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3022/search?q=makanan"
curl -s "http://localhost:3022/api/search?q=makanan&sort=best_seller&per_page=5" \
  | python -c "import sys,json; d=json.load(sys.stdin); print('items', len(d['items']), 'total', d['total'])"
```

Expected: status `200`; `items` > 0. Ini menguji jalur berbeda (`candidateIds` aktif karena ada kata kunci) yang sengaja TIDAK memakai kepala+ekor — pastikan tetap jalan.

- [ ] **Step 3: Cek jalur diskon masih benar**

```bash
curl -s "http://localhost:3022/api/search?discount_only=true&sort=best_seller&per_page=5" \
  | python -c "import sys,json; d=json.load(sys.stdin); print('total', d['total']); print('semua benar diskon:', all(i['discount_price'] is not None and i['discount_price'] < i['price_min'] for i in d['items']))"
```

Expected: tidak error. Kalau `total` = 0, itu **wajar dan sudah didokumentasikan** (spec §4.7: di Preview DB memang tidak ada diskon efektif) — laporkan apa adanya. Kalau ada item, semuanya harus `True`.

- [ ] **Step 4: Konfirmasi cakupan diff**

```bash
git diff --name-only origin/main...HEAD
```

Expected: tepat tiga path —
```
docs/superpowers/plans/2026-07-31-listing-pr3-sales-rank-cap-fix.md
docs/superpowers/specs/2026-07-07-listing-desktop-etalase-design.md
lib/search.ts
tests/search.test.ts
```
(empat baris; spec sudah di-commit sebelum plan). Pastikan TIDAK ada `app/products/**`, `app/search/page.tsx`, `components/**`, `flutter_app/**`, atau `prisma/schema.prisma`.

- [ ] **Step 5: Commit catatan verifikasi (kalau ada yang ditambahkan)**

```bash
git add -A
git commit -m "chore(search): catatan verifikasi PR3" --allow-empty
```

---

## Self-Review (dijalankan saat penulisan)

- **Cakupan spec:** Spec §4.7 mensyaratkan satu dari dua hal sebelum PR4 — "(a) ambil produk berdasarkan ranked-ids lebih dulu" atau "(b) naikkan batas". Rencana ini mengerjakan (a) dalam bentuk yang sudah dikoreksi di §4.8 (kepala ranked-ids + ekor belum-terjual), ditangani Task 2. Invarian "produk belum terjual tidak dibuang" dari §4.8 ditegakkan tes di Task 1. Batasan "PR3 backend saja" ditegakkan Task 3 Step 4.
- **Di luar cakupan (sengaja, milik PR4):** migrasi `/products`, sidebar filter, chip filter aktif, dropdown sort, bottom-sheet mobile, penindasan `ProductCatalogStickyHeader` di `md+`, empty state + "Terakhir kamu lihat", pembuangan filter `today`/`this-week`/`last-30-days`/`most-searched`/`most-bought`, default sort "Paling Populer". Semua sudah diputuskan owner di spec §4.8 dan menunggu PR4.
- **Pemindaian placeholder:** tidak ada — tiap langkah berisi kode/perintah literal.
- **Konsistensi tipe:** `orderDocsBySalesRank(docs, rankedIds, tiebreak)` didefinisikan di Task 1 dan dipakai dengan tanda tangan yang sama di Task 1 Step 5; `rankedIds: string[]` konsisten antara Task 1 dan Task 2; `CATALOG_FETCH_CAP`/`SALES_HEAD_CAP` didefinisikan di Task 2 Step 2 dan dipakai di Step 4.
- **Jebakan yang sengaja dicegah:** (1) `where` disebar ke KEDUA query supaya filter tidak bocor; (2) kepala hanya dipakai saat `!candidateIds` supaya jalur kata-kunci (dibatasi trigram 500 by design) tidak berubah; (3) `console.warn` dipindah ke `tail.length` supaya tidak false-positive saat `head + tail` kebetulan ≥ cap; (4) `getBestSellerProductIds`/`getTrendingProductIds` menerapkan `productRankWhere` (harga>0 & stok>0) pada ranking — karena ekor diambil dengan `where` biasa, produk stok-habis tetap muncul di ekor persis seperti sekarang, bukan ikut tersaring.
