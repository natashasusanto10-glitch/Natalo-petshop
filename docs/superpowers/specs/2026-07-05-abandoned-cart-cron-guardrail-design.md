# Abandoned-Cart Cron Guardrail — Design

## Problem

Akun user menerima notifikasi push "Item masih nunggu kamu" untuk produk
"Woo Nature's Touch Pet Wet Wipes", padahal cart yang user lihat di app
sama sekali tidak berisi produk itu (isinya 4 produk lain).

## Root Cause Investigation

Diagnostik read-only terhadap database produksi (`scripts/diag-abandoned-cart.mjs`,
dijalankan dengan izin eksplisit user) menemukan:

- Saat diperiksa, tidak ada row `CartItem` "Woo Wet Wipes" tersisa, dan
  cart server akun tersebut sudah berubah drastis (dari 4 item di
  screenshot menjadi 1 item beberapa jam kemudian) — membuktikan cart di
  server memang bisa menyimpang dari yang ditampilkan ke user pada suatu
  waktu.
- `PUT /api/cart` (`app/api/cart/route.ts`) memakai strategi
  **replace-total**: `deleteMany` semua row `CartItem` milik user, lalu
  `createMany` ulang persis payload yang dikirim client. Efeknya,
  `createdAt`/`updatedAt` setiap item ter-reset ke waktu sync terakhir,
  bukan waktu user benar-benar menambahkan produk itu pertama kali.
- Sync dari Flutter app ke server (`CartStore._scheduleRemoteSync` di
  `flutter_app/lib/state/cart_store.dart`) bersifat **debounced 800ms,
  fire-and-forget, tanpa retry** — kalau gagal (app ditutup/background,
  sinyal putus) sebelum debounce selesai, kegagalan itu diam-diam.
- Kombinasi keduanya: kalau sync untuk sebuah penghapusan item gagal,
  row item itu ("hantu") tetap tertinggal di server dengan status belum
  checkout. Cron `GET /api/cron/abandoned-cart` membaca langsung dari
  tabel ini tanpa validasi tambahan, sehingga ikut menganggapnya
  "abandoned" dan mengirim notifikasi — padahal user sudah
  menghapusnya di app.
- Temuan tambahan (di luar scope perbaikan ini, dicatat untuk referensi):
  `CartStore.loadFromServer()` — fungsi yang menurut doc comment-nya
  "dipanggil saat user login" untuk menarik cart dari device lain —
  ternyata **tidak pernah dipanggil di mana pun** dalam kode Flutter app.
  Ini bug terpisah yang relevan untuk perbaikan sync mechanism (bagian B,
  tidak termasuk spec ini).

## Scope

Spec ini **hanya mencakup perbaikan di sisi cron**
(`app/api/cron/abandoned-cart/route.ts`). Spec ini **tidak** mengubah
mekanisme sync `PUT /api/cart` atau `cart_store.dart` — perbaikan akar
penyebab (sync yang fire-and-forget tanpa retry) adalah pekerjaan
terpisah ("bagian B") yang sengaja tidak digabung ke sini.

Konsekuensi dari batasan ini (disetujui user secara eksplisit): fix ini
**mengurangi peluang** notifikasi salah sasaran, bukan menghilangkan
akar penyebabnya sepenuhnya. Row hantu masih bisa lolos kalau user tidak
melakukan aksi cart apa pun dalam jendela toleransi (lihat Guardrail 2).

## Design

### Guardrail 1 — Skip produk yang sudah tidak bisa dibeli

Sebelum membentuk batch notifikasi, cron memvalidasi tiap item lewat
helper yang **sudah ada** di codebase: `getCartStockSnapshots()` di
`lib/cart-stock-server.ts` (fungsi yang sama dipakai `GET /api/cart`
untuk reconcile cart normal terhadap stok).

Perubahan di `app/api/cron/abandoned-cart/route.ts`:

- Query `prisma.cartItem.findMany` menambah field ke `select`:
  `productId`, `variantId`, `variantLabel`, `quantity` (kolom-kolom ini
  sudah ada di model `CartItem`, sebelumnya tidak ikut di-select oleh
  cron).
- Setelah fetch, panggil `getCartStockSnapshots(items)` untuk
  mendapatkan `isAvailable` per item (produk nonaktif, dihapus, stok 0,
  atau varian sudah tidak ada/nonaktif → `isAvailable: false`).
- Item dengan `isAvailable === false` **di-drop** dari batch — tidak
  ikut dihitung ke preview push, dan **tidak** di-mark
  `notifiedAbandonedAt` maupun `abandonedCandidateAt` (supaya kalau
  stok kembali tersedia dalam window 7 hari, item tetap bisa
  dipertimbangkan wajar di run berikutnya).
- Kalau setelah filter ini seorang user tidak punya item valid sama
  sekali, user tersebut di-skip total untuk run ini (tidak kirim push
  kosong).

### Guardrail 2 — Konfirmasi dua-putaran-berturut sebelum kirim

**Tujuan:** memberi satu siklus cron tambahan (~1 jam) supaya row hantu
punya kesempatan "sembuh sendiri" — karena `PUT /api/cart` replace-total
berarti aksi cart apa pun oleh user (bahkan tidak terkait item yang
dicurigai) akan menghapus-dan-membuat-ulang SEMUA row cart user itu,
otomatis membersihkan row hantu tanpa perlu logic tambahan.

**Migration:** tambah kolom nullable baru ke model `CartItem` di
`prisma/schema.prisma`:

```prisma
model CartItem {
  // ...kolom existing tidak berubah...
  notifiedAbandonedAt   DateTime?
  // Tanda "pertama kali dicurigai abandoned" oleh cron — dipakai untuk
  // syarat 2-putaran-berturut sebelum benar-benar kirim notifikasi.
  // Reset otomatis jadi null setiap kali row ini disinkron ulang (row
  // lama di-delete, row baru dibuat oleh PUT /api/cart replace-total),
  // sehingga tidak perlu invalidasi manual.
  abandonedCandidateAt  DateTime?
  createdAt             DateTime  @default(now())
  updatedAt             DateTime  @updatedAt

  @@unique([userId, productId, variantId])
  @@index([userId])
  @@index([notifiedAbandonedAt, createdAt])
}
```

Kolom baru nullable, default `null`, tidak perlu backfill data lama.

**Logic cron (setelah lolos Guardrail 1):**

- Kalau `abandonedCandidateAt == null` → ini pertama kali cron
  mencurigai item ini abandoned. Update row: set
  `abandonedCandidateAt = now()`. **Jangan** masukkan ke batch notifikasi
  run ini.
- Kalau `abandonedCandidateAt != null` (sudah dicurigai sejak run
  sebelumnya, dan row-nya masih ada/tidak tersentuh) → masukkan ke batch
  notifikasi run ini (grouping by user seperti logic existing), lalu
  set `notifiedAbandonedAt = now()` setelah push terkirim (tidak
  berubah dari behavior sekarang).

**Trade-off yang disetujui user secara eksplisit:** SEMUA notifikasi
abandoned-cart (termasuk yang sah, bukan row hantu) mundur kira-kira 1
jam dari waktu saat ini. Item yang melewati ambang 4 jam pada jam 21:00
baru benar-benar terkirim sekitar jam 22:00 kalau tidak ada aktivitas
cart apa pun dari user di jam tersebut. Ini perubahan timing yang
disengaja, bukan efek samping tidak terduga.

### Observability

Response JSON cron ditambah breakdown supaya gampang dipantau lewat log
Vercel tanpa perlu query DB manual kalau ada laporan serupa:

```json
{
  "ok": true,
  "checked": 0,
  "skippedUnavailable": 0,
  "markedAsCandidate": 0,
  "usersTotal": 0,
  "notified": 0,
  "failedUsers": 0
}
```

## Data Flow (urutan eksekusi baru di cron)

1. Query `CartItem` eligible by age — logic window (4 jam - 7 hari)
   tidak berubah, hanya tambah field di `select`.
2. **Guardrail 1:** `getCartStockSnapshots(items)` → buang item
   `isAvailable === false`.
3. **Guardrail 2:** pisah sisa item:
   - `toMark` (`abandonedCandidateAt == null`) → update jadi `now()`,
     tidak masuk batch notifikasi.
   - `toNotify` (`abandonedCandidateAt != null`) → masuk batch
     notifikasi.
4. Kirim push untuk `toNotify`, grouping by user (logic existing tidak
   berubah) → set `notifiedAbandonedAt`.
5. Return response JSON dengan breakdown lengkap.

## Error Handling

Mengikuti pola yang sudah ada di route ini: tiap DB update
(`updateMany` untuk `abandonedCandidateAt`, dan untuk
`notifiedAbandonedAt`) dibungkus `.catch(() => {})`, dan pengiriman push
per-user tetap pakai `Promise.allSettled` — satu user gagal tidak
menggagalkan seluruh batch.

## Testing Plan

Unit test untuk `app/api/cron/abandoned-cart/route.ts` (Prisma test
client / mock), skenario:

1. Item dengan produk stok habis / nonaktif → di-skip, tidak ada field
   (`notifiedAbandonedAt` maupun `abandonedCandidateAt`) yang berubah.
2. Item baru pertama kali eligible (`abandonedCandidateAt` masih null)
   → `abandonedCandidateAt` ter-set ke waktu sekarang, tidak ada push
   terkirim.
3. Item yang sudah punya `abandonedCandidateAt` dari run sebelumnya
   (dan masih eligible) → push terkirim, `notifiedAbandonedAt` ter-set.
4. Campuran multi-user dalam satu run cron tidak saling memengaruhi
   hasil satu sama lain.

Tidak ada perubahan Flutter/UI pada spec ini, jadi tidak perlu
verifikasi emulator/browser.

## Out of Scope (dicatat untuk pekerjaan selanjutnya)

- Perbaikan mekanisme sync `PUT /api/cart` (ubah dari replace-total ke
  diff/upsert) dan keandalan `_scheduleRemoteSync` di
  `cart_store.dart` (retry, bukan fire-and-forget) — ini "bagian B".
- `CartStore.loadFromServer()` yang tidak pernah dipanggil di mana pun
  meski doc comment-nya menjanjikan itu jalan saat login — bug terpisah,
  relevan untuk bagian B.
