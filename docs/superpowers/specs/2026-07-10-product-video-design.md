# Video Produk — Spec Desain

Tanggal: 2026-07-10
Status: menunggu review user
Scope fase ini: pipeline admin (Next.js) + tampilan app Flutter (Beranda grid autoplay + detail).
Ditunda: tampilan web (grid + detail Next.js storefront).

## Ringkasan

Admin bisa melampirkan **satu video** ke produk lewat halaman Edit Produk (web admin).
Video di-transcode otomatis oleh **Bunny Stream** di **library terpisah dari feed**.
Di **app Flutter**: card grid Beranda memutar video otomatis (muted, loop, hanya saat
terlihat) ala Shopee; halaman detail menaruh video sebagai **slide #1** galeri dengan
thumbnail + tombol play (tanpa autoplay).

## Keputusan kunci (dan alasannya)

| Keputusan | Alasan |
|---|---|
| Bunny Stream, bukan UploadThing | Admin tidak tahu/tidak bisa kontrol ukuran & resolusi video sumber (HP merekam 1080p/4K, 50–200MB). Wajib transcoding server-side. UploadThing tidak transcode. |
| **Library Bunny terpisah** (`BUNNY_PRODUCT_*`) | `lib/feed/bunny-gc.ts` menyapu SELURUH library feed dan menghapus video yang GUID-nya tidak dipakai FeedPost aktif. Video produk di library yang sama akan **terhapus oleh cron GC feed**. Pemisahan library = keharusan, bukan kerapian. |
| Deteksi otomatis MB/resolusi/durasi di client | Admin "tidak tahu berapa MB dan HD atau tidak" — sistem baca `file.size` + `readVideoMetadata()` (sudah ada di `lib/feed/video-thumbnail.ts`) dan tampilkan `12.4 MB · 1080×1920 · 24 dtk` + verdict valid/tolak dengan alasan. |
| Dengan trim (reuse trimmer feed) | Pilihan user. Reuse `lib/feed/video-trimmer.ts` + UI timeline filmstrip dari `FeedUploadClient`. |
| Auto-thumbnail Bunny | Pilihan user. Bunny ambil frame ~10% klip saat selesai proses; nol kerja ekstra. |
| TUS resumable upload | File bisa ratusan MB di koneksi mobile; reuse `uploadToBunnyViaTus` + `generateBunnyTusCredentials`. Bypass limit body Vercel ~4.5MB. |
| Flutter dulu, web ditunda | Pilihan user. |
| Autoplay grid hanya card terlihat, maks 2–3 bersamaan | Pilihan user ("hanya yang terlihat"). Hemat data/baterai, scroll mulus di HP low-end. |

## Batasan video (konstanta baru `PRODUCT_VIDEO_CONFIG`)

- Durasi hasil trim: **10–60 detik** (min 10 supaya layak jadi video produk; bisa diubah).
- Ukuran file sumber: maks **200 MB** (sama dengan `MAX_SOURCE_VIDEO_SIZE` feed).
- Format: `video/*` (MP4/MOV/WebM) — Bunny yang normalisasi ke HLS + MP4 fallback.
- Encoding target diatur di **dashboard Bunny library produk** (bukan di kode):
  720p H.264 utama + varian rendah (240/360p) untuk grid autoplay. MP4 Fallback ON.

## A. Arsitektur & pemisahan library

Modul baru `lib/product/product-video.ts`:

- Baca env **`BUNNY_PRODUCT_LIBRARY_ID`**, **`BUNNY_PRODUCT_API_KEY`**,
  **`BUNNY_PRODUCT_CDN_HOSTNAME`**, opsional **`BUNNY_PRODUCT_WEBHOOK_SECRET`**,
  opsional **`BUNNY_PRODUCT_TOKEN_SECURITY_KEY`**.
- Fungsi: `getProductBunnyConfig()`, `createProductVideo()`, `deleteProductVideo()`,
  `getProductVideo()`, `productPlaylistUrl()`, `productMp4Url()`, `productThumbnailUrl()`,
  `generateProductTusCredentials()`, `listProductLibraryVideos()`.
- Implementasi meniru `lib/feed/bunny.ts` (pola sudah terbukti) tapi **tidak mengimpor
  config feed** dan **tidak menyentuh kode feed sama sekali** — zero regresi ke feed.
- Refactor bersama HANYA untuk helper murni tanpa env (mis. format signature TUS) bila
  trivially aman; kalau ragu, duplikasi kecil lebih aman daripada coupling.

## B. Perubahan DB — model `Product` (migrasi Prisma)

```prisma
// Video produk (Bunny Stream, library terpisah dari feed).
videoUrl          String?  // HLS playlist.m3u8 dari CDN Bunny; null = tidak ada video
videoGuid         String?  @unique // GUID Bunny — dipakai webhook + GC produk
videoStatus       String?  // "uploading" | "processing" | "ready" | "failed"; null = tidak ada
videoThumbnailUrl String?  // auto-thumbnail Bunny, diisi saat ready
videoDurationSec  Int?
```

Satu video per produk (ganti = hapus lama + upload baru). Migrasi butuh DATABASE_URL —
**gate: tidak bisa dijalankan di sandbox**, jalankan `prisma migrate dev` di mesin user.

## C. Editor admin — section "Video Produk"

Lokasi: `app/admin/(protected)/products/[id]/edit/page.tsx`, `SectionCard` baru
di dalam blok **Informasi Dasar**, tepat di bawah area foto (`MultiImageUpload`).
Komponen client baru: `components/admin/ProductVideoUpload.tsx`.

### State kosong (belum ada video)

- Slot dashed + ikon video + teks placeholder aturan:
  "MP4/MOV · 10–60 detik · maks 200 MB · disarankan 1080p".
- Tombol "Pilih Video".

### Alur upload

1. **Pilih file** → langsung `readVideoMetadata(file)` + `file.size`.
2. **Kartu info otomatis**: `{formatFileSize(size)} · {width}×{height} · {durasi} dtk`
   + label kualitas ("HD 1080p" / "HD 720p" / "SD") — menjawab "admin tidak tahu MB/HD".
3. **Validasi client**: size > 200MB → tolak dengan alasan + saran; durasi < 10 dtk →
   tolak; durasi > 60 dtk → wajib trim dulu (langkah 4).
4. **Trim** (selalu tersedia, wajib bila > 60 dtk): timeline filmstrip + handle
   kiri/kanan, reuse pola `TrimScreen`/`Filmstrip` dari `FeedUploadClient` +
   `trimVideo()` dari `lib/feed/video-trimmer.ts`. Preview loop dalam range terpilih.
5. **Provision**: `POST /api/admin/products/[id]/video` → server buat video di library
   produk (`createProductVideo`, title `product-{id}`), set `videoGuid` +
   `videoStatus="uploading"` di DB, balikan TUS credentials.
6. **Upload**: client TUS resumable (`uploadToBunnyViaTus`) dengan progress bar %.
7. **Selesai upload**: client `PATCH /api/admin/products/[id]/video` → server set
   `videoStatus="processing"`, `videoDurationSec`. UI tampil badge "Sedang diproses…"
   (video belum tampil di toko).
8. **Webhook**: `POST /api/products/bunny/webhook` (route baru, verifikasi
   `BUNNY_PRODUCT_WEBHOOK_SECRET`) — saat `Status=4 (FINISHED)` set
   `videoUrl` (playlist HLS), `videoThumbnailUrl`, `videoStatus="ready"`;
   saat `Status=5 (ERROR)` set `"failed"`. Cari row via `videoGuid`.
9. **Gagal di tengah** (client crash / TUS error): tombol "Coba lagi" (TUS resume)
   atau "Batalkan" → `DELETE` endpoint → hapus di Bunny + null-kan semua field video.

### State ada video

- Preview thumbnail + durasi + status badge (`ready` hijau / `processing` amber /
  `failed` merah dengan tombol ulang).
- Tombol **Hapus Video** (ConfirmDialog) → `DELETE /api/admin/products/[id]/video`
  → `deleteProductVideo(guid)` best-effort + null-kan field. Ganti video = hapus → upload.

### Endpoint admin (semua auth admin, pola sama dengan API admin lain)

- `POST   /api/admin/products/[id]/video` — provision + TUS creds.
- `PATCH  /api/admin/products/[id]/video` — tandai upload selesai (`processing`).
- `DELETE /api/admin/products/[id]/video` — hapus Bunny + reset field.
- `POST   /api/products/bunny/webhook` — callback Bunny (tanpa auth admin, pakai secret).

## D. Tampilan app Flutter

### D1. Beranda — grid autoplay (`_HomeProductCard`)

- Kalau produk punya `videoStatus == "ready"` dan `videoUrl` → area cover 1:1 memutar
  **MP4 240p/360p** (`productMp4Url` varian rendah) — muted, loop, tanpa kontrol,
  `fit: cover`, menggantikan foto.
- **Visibility-aware**: `visibility_detector`; video main hanya saat fraksi terlihat
  ≥ ~60%. Pool `VideoPlayerController` terbatas **maks 2–3 aktif** (LRU): card keluar
  viewport → pause + dispose controller.
- **Fallback wajib**: sebelum controller ready / error / status bukan ready → tampil
  foto cover biasa (`AppProductImage`). Tidak boleh ada kotak hitam/skeleton video.
- Gotcha dari memori grid-shopee: `_HomeProductCard` dipakai juga oleh section
  Terlaris/empty-cart reuse — perilaku autoplay diberi flag supaya bisa dimatikan per
  konteks bila perlu.
- Card lain (Katalog `_ProductsPageProductCard`, Cart/Wishlist compact) TIDAK autoplay
  di fase ini — cukup Beranda dulu (badge ▶ kecil opsional di Katalog, keputusan saat
  implementasi).

### D2. Detail produk — video slide #1, manual play

- Galeri detail: kalau video ready → **item pertama** carousel = thumbnail Bunny
  (`videoThumbnailUrl`) + tombol ▶ overlay di tengah + badge durasi.
- Tekan ▶ → play inline **720p MP4** dengan suara + kontrol dasar (pause/seek/mute).
  Tidak autoplay. Swipe ke slide lain → pause.
- Foto-foto produk menyusul di slide 2+ (urutan existing tidak berubah).

### D3. API produk untuk Flutter

- Endpoint produk yang dikonsumsi Flutter (list beranda + detail) menambah field
  `videoUrl`, `videoThumbnailUrl`, `videoDurationSec` — **hanya di-serialize bila
  `videoStatus == "ready"`** (selain itu null/absen). Client Flutter lama yang belum
  kenal field ini tetap aman (additive, non-breaking).
- Bila token authentication Bunny diaktifkan untuk library produk, URL di-sign
  server-side (pola `signBunnyUrl`) sebelum dikirim.

## E. GC video produk

- `lib/product/product-video-gc.ts` — analog `bunny-gc.ts`: kumpulkan `videoGuid` dari
  semua Product (aktif + arsip — arsip bisa dipulihkan, videonya jangan disapu),
  paginate library produk, hapus GUID yang tidak direferensikan (orphan dari upload
  gagal/batal).
- Dipanggil dari cron route yang sama dengan GC feed (tambah langkah) atau route cron
  terpisah — keputusan implementasi, ikut pola cron existing.
- Hard-delete produk (single + bulk `/api/admin/products/bulk`) ikut memanggil
  `deleteProductVideo(guid)` best-effort supaya tidak menunggu GC.

## Error handling — ringkasan

| Kondisi | Perilaku |
|---|---|
| File > 200MB / durasi invalid | Ditolak di client dengan alasan spesifik + saran |
| Bunny env produk belum di-set | Section video tampil disabled + pesan "belum dikonfigurasi" (`isProductBunnyConfigured()`); fitur lain normal |
| Upload putus | TUS resume; atau Batalkan → cleanup |
| Webhook tidak datang | Status stuck `processing`; tombol "Cek status" di editor memanggil `getProductVideo(guid)` untuk reconcile manual (pola `reconcile.ts` feed) |
| Encoding gagal (Status=5) | `videoStatus="failed"`, editor tampil error + tombol hapus/ulang; toko tidak terpengaruh |
| Video error load di Flutter | Fallback foto cover; tidak ada UI rusak |

## Testing & verifikasi

- **Web**: `npx tsc --noEmit` + `npx eslint` wajib 0 error. Runtime & webhook TIDAK bisa
  diuji di sandbox (tanpa DATABASE_URL + tanpa akun Bunny library baru) — **gate
  smoke-test manual** sebelum merge, sama seperti PR admin sebelumnya.
- **Flutter**: `flutter analyze` + widget test existing tetap hijau; test baru untuk
  logika pool controller (unit) bila praktis. Gotcha shimmer/pumpAndSettle dari memori
  berlaku. Device-verify autoplay di HP nyata = gate sebelum rilis.

## Deploy gates (urutan)

1. Buat **library Bunny baru** khusus produk di dashboard (encoding 720p + varian rendah,
   MP4 Fallback ON, webhook URL di-set) → isi env `BUNNY_PRODUCT_*` di Vercel.
2. `prisma migrate dev` (field video di Product) di mesin dengan DATABASE_URL.
3. Merge web admin → smoke test upload end-to-end (upload → processing → ready).
4. Rilis Flutter (grid autoplay + detail) setelah API produk ter-deploy.

## Di luar scope fase ini

- Tampilan web storefront (grid + detail Next.js) — fase berikutnya.
- Autoplay di Katalog/Cart/Wishlist Flutter.
- Multi-video per produk; pilih frame thumbnail manual; upload video dari app Flutter.
