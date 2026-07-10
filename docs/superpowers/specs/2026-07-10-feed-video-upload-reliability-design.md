# Feed Video Upload Reliability — Fase 1 Design

**Tanggal:** 2026-07-10
**Status:** Disetujui user (approach "A — patch bedah")
**Fase 2 (terpisah, nanti):** redesign UX flow posting menyamai IG (picker inline, edit fullscreen ala IG, preview dengan feed-chrome asli + suara, edit cover scrubber, Save draft + Share berdampingan) — termasuk melebur ide "pindahkan trim+kompres ke background store" (approach B).

## Masalah

User sering gagal posting video (sumber video umumnya download-an WhatsApp, MP4 H.264). Gagal muncul di dua titik sama sering: (a) layar Edit Video — "Video belum berhasil diproses. Coba lagi.", (b) layar/relay upload — "Upload belum berhasil...". Ditambah 2 bug UX fatal:

1. **Dead-end error di Edit Video** — saat kompresi gagal, `_error` di-set dan tidak pernah bisa clear: tombol Next disabled (`_loading || _exporting || _error != null`) dan `_exportTrim()` early-return saat `_error != null`. Pesan "Coba lagi" tidak punya kontrol yang bisa retry.
2. **Swipe back → langsung error** — `FeedVideoTrimScreen.dispose()` memanggil `VideoCompress.cancelCompression()` tanpa syarat. `VideoCompress` adalah singleton global:
   - swipe back saat export jalan → kompresi dibatalkan paksa → plugin bisa nyangkut di state "sedang kompres" → percobaan berikutnya langsung throw;
   - kalau background upload store sedang kompres dan layar trim di-dispose, kompresi milik store ikut terbunuh.

Temuan tambahan dari pembacaan kode:

3. **TUS upload tanpa retry** — `TusClient` dibuat tanpa parameter `retries` (`bunny_upload_service.dart`). Gangguan jaringan sesaat = seluruh upload gagal, padahal `tus_client_dart` support auto-retry + sudah pakai `TusFileStore` (resume dari byte terakhir).
4. **Video pendek di-upload tanpa kompres** — `FeedVideoPreviewScreen._next()` mengisi `trimmedVideoPath` dengan path video asli mentah (bukan hasil kompres). `FeedUploadStore._runVideoUpload()` melihat `trimmedVideoPath != null` → mengira sudah terkompres → skip kompres 720p → upload file mentah (lebih besar, lebih lama, lebih gampang gagal). Video ≤60 detik (mayoritas video WhatsApp) kena jalur ini.

## Scope

Hanya keandalan pipeline (kompresi + upload). **Tidak menyentuh tampilan/layout** — itu Fase 2. File yang disentuh:

- `flutter_app/lib/screens/feed_video_upload_flow.dart`
- `flutter_app/lib/state/feed_upload_store.dart`
- `flutter_app/lib/services/bunny_upload_service.dart`
- (baru) helper `VideoCompressGate` — lokasi wajar: `flutter_app/lib/services/video_compress_gate.dart`

## Desain Fix

### Fix 1 — Retry beneran di Edit Video
- `_exportTrim()`: hapus `_error != null` dari guard early-return; di awal eksekusi clear `_error`.
- Tombol Next (`_RoundNextButton`): kondisi disable jadi hanya `_loading || _exporting`.
- Hasil: saat error, tap Next = retry sungguhan.

### Fix 2 — `VideoCompressGate` (guard singleton)
Helper kecil yang jadi satu-satunya pintu ke `VideoCompress.compressVideo`:
- **Serialisasi:** antrian internal (mutex/future-chain) — tidak pernah 2 kompresi konkuren; pemanggil kedua menunggu, bukan crash.
- **Cancel ber-scope:** `cancel(token)` hanya membatalkan job milik pemanggil itu; dispose layar trim tidak lagi memanggil `cancelCompression()` global — hanya cancel job miliknya sendiri, dan hanya kalau `_exporting`.
- **Reset state nyangkut:** sebelum mulai job baru, kalau plugin masih klaim "sedang kompres" padahal tidak ada job aktif di gate → panggil `cancelCompression()` + delay singkat untuk reset.
- Dipakai di 3 call-site: layar trim (`_exportTrim`), store background (`_runVideoUpload` step 0), layar progress legacy (`FeedUploadProgressScreen._startUpload`).

### Fix 3 — TUS auto-retry
- `uploadViaTus`: tambahkan `retries: 3`, `retryScale` exponential, `retryInterval` ~2 detik pada `TusClient`.
- `TusFileStore` yang sudah ada membuat retry lanjut dari byte terakhir, bukan dari 0%.

### Fix 4 — Video pendek dikompres lagi
- `FeedVideoPreviewScreen._next()`: hapus `copyWith(trimmedVideoPath: ..., trimmedDuration: ...)` — teruskan `widget.draft` apa adanya (`trimmedVideoPath` tetap `null`).
- Store kembali mengkompres video pendek (720p) sebelum TUS.
- Validasi `FeedNewPostScreen._upload()` tetap jalan (getter di `FeedCreatePostDraft` sudah diverifikasi): `finalVideoPath => trimmedVideoPath ?? localVideoPath` dan `finalDuration => trimmedDuration ?? originalDuration` — dua-duanya terisi dari `localVideoPath`/`originalDuration`.

### Fix 5 — Swipe-back aman saat proses
- `FeedVideoTrimScreen` dapat `PopScope`: `canPop = !_exporting`.
- Saat `_exporting` dan user back/swipe → dialog konfirmasi "Video sedang diproses — batalkan?" → kalau ya: cancel bersih via gate, reset state, lalu pop.
- Saat tidak exporting, back bebas seperti sekarang.

## Error handling (tidak berubah, dikonfirmasi tetap)
- Kompresi gagal di store → fallback upload original (sudah ada, dipertahankan).
- Kompresi gagal di layar trim → error box tetap tampil, tapi kini dengan jalan keluar (retry via Next / back aman).
- Teks pesan error existing dipertahankan.

## Testing
- `flutter analyze` bersih + widget test existing hijau.
- Unit test `VideoCompressGate`: serialisasi (2 job konkuren → berurutan), cancel ber-scope (cancel job A tidak mematikan job B), reset state nyangkut.
- **Device verify wajib** (plugin native tidak ter-cover unit test): video WhatsApp >60s (jalur trim), ≤60s (jalur langsung — cek log kompresi jalan), swipe-back saat proses, matikan WiFi sesaat di tengah upload (cek TUS resume).

## Non-goals (Fase 2)
- Redesign layar picker/edit/share-sheet/preview menyamai IG.
- Suara di preview + preview feed-chrome asli (bug #3 & #4 laporan awal).
- Memindahkan trim+kompres ke background store (approach B).
- Streaming `uploadViaPut` (fallback path jarang terpakai; `readAsBytes` OOM-risk dicatat, ditunda).
