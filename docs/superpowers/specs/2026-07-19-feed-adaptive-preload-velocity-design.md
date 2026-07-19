# Preload Adaptif Kecepatan Scroll (Feed) — Desain v1 (Opsi A)

**Tanggal:** 2026-07-19
**Konteks:** Lanjutan pasca migrasi Feed → `PostVideoCoordinator` (Langkah 1-7 selesai; Feed kini satu engine tanpa flag). Ini kandidat upgrade "A" — preload adaptif (D2 yang sempat di-defer).

## Masalah

`AdaptiveVideoPreloadPolicy.offsets()` sudah adaptif terhadap arah swipe, tier jaringan, buffer-ahead, dan preferensi user — tapi **buta terhadap kecepatan fling**. Window-nya statis per-kondisi (`[dir, dir*2, -dir]` di wifi). Saat user fling cepat melewati beberapa item, preload tetap menyasar index+1/+2 dari posisi sekarang — video tujuan (beberapa item ke depan) tak sempat ter-preload → tetap muncul spinner.

## Ruang lingkup (v1 = Opsi A)

**Termasuk:** melebarkan/menyempitkan preload window berdasar magnitude kecepatan fling, **wifi-only**.

**TIDAK termasuk (YAGNI, ditunda ke v2 bila device-verify menunjukkan perlu):**
- Prediksi titik-henti (at-rest prediction) untuk fling ekstrem.
- Velocity-adaptation di cellular (dijaga hemat kuota — cabang cellular tak tersentuh).
- Formula kontinu (pakai tangga 3-kategori) & cap dinamis per-kategori.

## Desain

### Sumber sinyal
`DragEndDetails.primaryVelocity` (px/s) dari `PageView`, ditangkap via `NotificationListener<ScrollEndNotification>` — `dragDetails` hanya non-null pada scroll-end akibat drag-release (bukan settle balistik), jadi ini nilai fling murni yang fire SEBELUM page settle → segar saat `_onPageChanged` memicu preload. Disimpan di field `_lastFlingVelocity` (default 0).

### Kontrak `offsets()`
Tambah `double scrollVelocity = 0`. Default 0 = perilaku legacy byte-for-byte (backward-compatible; test lama tetap hijau). Logika velocity **hanya** di cabang wifi-generous (`auto`/`high`); cabang cellular/unknown/offline/data_saver/locked tak berubah.

### Tabel window (wifi, `dir` = arah gerak, `speed` = |velocity|)

| Kategori | `speed` px/s | Window offsets |
|---|---|---|
| Lambat/diam | `< 800` | `[dir, dir*2, -dir]` (legacy) |
| Sedang | `800 ≤ speed ≤ 2500` | `[dir, dir*2, dir*3, -dir]` |
| Cepat | `> 2500` | `[dir, dir*2, dir*3, dir*4]` (buang `-dir`) |

Ambang `mediumFlingVelocity=800` / `fastFlingVelocity=2500` = konstanta bernama, di-tuning saat device-verify.

### Cap memori
`maxPreloads` 3 → 4 (menampung window Cepat). LRU coordinator tetap mengevakuasi controller terlama → live-session count tetap terbatas (~4 steady-state).

## Titik integrasi
- `adaptive_video_preload_policy.dart` — pure function, +1 param +logika tangga.
- `feed_screen.dart` — field `_lastFlingVelocity`; `NotificationListener` menangkap velocity; `_managePreloadWindow` meneruskan `scrollVelocity`. Struktur attach/setActive/detach §Urutan #1/#2 dan kontrak `setPreloadWindow` **tak berubah**.

## Testing
- **Unit `offsets()`** (risiko utama, TDD penuh + teeth-verified via mutasi): tiap kategori × arah (fwd/bwd) × jaringan; regresi "velocity 0 = identik legacy"; guard "velocity tak melebar cellular/unknown"; guard "velocity tak menghidupkan window yang disabled".
- **Plumbing** (field + notification + arg): tipis; dicakup `flutter analyze` + device-verify (pure decision logic sudah ter-cover unit).
- **Device-verify:** scroll pelan / fling sedang / fling cepat / balik arah mendadak → cek instan vs boros kuota vs jank memori low-end. Sesuaikan ambang px/s bila perlu.

## Rollback
Revert commit tunggal. Karena `scrollVelocity` berdefault 0, mengembalikan field ke 0 (atau mencabut wiring) memulihkan perilaku legacy tanpa menyentuh cabang lain.
