# Comment Drawer — Remove Pull-to-Refresh, Faster Auto-Poll

**Date:** 2026-07-18
**Scope:** Daftar komentar `FeedCommentSheet` (Feed video + foto/carousel + modal Postingan) dan `FeedCommentSyncCoordinator`
**Status:** Approved design

## Problem Statement

Setelah menambahkan pull-to-dismiss (tarik daftar komentar ke bawah saat di
puncak → tutup sheet), daftar komentar masih dibungkus
`NataloPawRefreshIndicator`. Akibatnya satu gerakan tarik-bawah-di-puncak
memicu **dua perilaku sekaligus**: spinner pull-to-refresh MUNCUL sementara
sheet ikut menyusut/menutup. Gesture jadi ambigu dan tidak konsisten dengan
IG Reels, yang memakai tarik-bawah-di-puncak semata-mata untuk **menutup**
sheet (tanpa pull-to-refresh).

## Decision

Buang pull-to-refresh dari daftar komentar di SEMUA surface, dan andalkan
auto-poll yang sudah ada — dipercepat agar terasa "hidup".

### 1. Hapus `NataloPawRefreshIndicator` dari daftar komentar

Di `_buildListBody` (`lib/widgets/feed_comment_sheet.dart`):

- **State populated** (list komentar): lepaskan pembungkus
  `NataloPawRefreshIndicator`, sisakan `ListView.builder` langsung. Tarik-bawah
  di puncak kini hanya menutup sheet (via pull-to-dismiss di Feed, via coupling
  framework + terminal guard di modal).
- **State error**: lepaskan pembungkus `NataloPawRefreshIndicator`; ganti
  mekanisme retry dengan tombol eksplisit **"Coba lagi"** yang memanggil
  `_refresh`. Tarik-bawah tetap konsisten = tutup.
- **Skeleton (loading)** dan **empty state**: sudah tanpa refresh indicator —
  tidak berubah.

Perubahan bersifat **tanpa syarat** (bukan per-surface). `FeedCommentSheet`
di-share, sehingga menghapus pembungkus di `_buildListBody` menghilangkan
pull-to-refresh sekaligus di Feed dan modal Postingan. Modal tetap menutup
secara alami saat ditarik di puncak (coupling framework + terminal-extent guard
0.205 yang sudah ada), jadi perilaku "tarik = tutup" konsisten di semua surface.

`_refresh` TIDAK dihapus — masih dipakai oleh tombol "Coba lagi" dan oleh
auto-poll.

### 2. Percepat auto-poll 10 detik → 5 detik

`FeedCommentSyncCoordinator` (`lib/state/feed_comment_sync_coordinator.dart`)
sudah merevalidasi komentar tiap 10 detik selama sheet terbuka dan app aktif,
serta memicu satu tick saat app kembali ke foreground
(`didChangeAppLifecycleState`). Ubah `interval` default dari 10 detik menjadi
**5 detik** agar komentar dari user lain masuk lebih cepat (maks ~5 detik).

Sifat coordinator tidak berubah: berhenti saat app di background, hanya jalan
saat ada drawer terdaftar, dan men-serialize request per key (tidak ada
duplikasi). Beban jaringan tetap terbatas.

## Freshness Model (setelah perubahan)

- Komentar user sendiri: **instan** (optimistic insert) — tidak berubah.
- Komentar user lain: masuk otomatis maks **~5 detik** via auto-poll.
- Buka sheet: `_loadInitial` memuat penuh.
- Kembali ke foreground: satu tick refresh (sudah ada).
- Gagal muat (state error + belum ada komentar): tombol **"Coba lagi"**.

### Konsekuensi yang diterima

- Tidak ada lagi pull-to-refresh manual. Jika komentar sudah tampil lalu
  jaringan putus, auto-poll gagal diam-diam (best-effort) dan user melihat
  komentar agak basi sampai poll berikutnya berhasil, kembali foreground, atau
  tutup-buka sheet. Ini kompromi yang diterima; sejalan dengan IG.
- Frekuensi request 2× saat sheet terbuka. Bounded (hanya saat terbuka +
  foreground).

## Out of Scope

- Realtime murni (websocket/push) untuk komentar.
- Perubahan visual/warna/tinggi sheet, composer, atau reaction bar.
- Perubahan pada Feed video/foto utama (bukan daftar komentar).
- Logika pull-to-dismiss dan terminal-state reliability (sudah ada; tidak
  diubah).

## Testing

- **Widget test daftar Feed populated**: assert TIDAK ada
  `NataloPawRefreshIndicator`/`RefreshProgressIndicator` di subtree daftar
  komentar saat ada komentar.
- **Widget test state error**: assert ada tombol "Coba lagi"; tap memanggil
  ulang pemuatan; TIDAK ada refresh indicator.
- **Anchor pull-to-dismiss (regresi bentrok)**: dengan daftar tanpa refresh
  indicator, tarik-bawah-di-puncak hanya memicu pull-to-dismiss (bukan refresh).
- **Coordinator interval**: assert `interval` default = 5 detik; `debugTick`
  tetap memanggil callback refresh; tidak ada request duplikat per key.
- **Regresi**: seluruh test comment drawer + video adapter yang ada tetap lulus;
  `flutter analyze` bersih pada file yang disentuh.

## Acceptance Criteria

1. Tarik-bawah daftar komentar saat di puncak = menutup sheet; tidak ada
   spinner pull-to-refresh, di Feed maupun modal Postingan.
2. State error menampilkan tombol "Coba lagi" yang memuat ulang komentar.
3. Auto-poll berjalan tiap 5 detik selama sheet terbuka + app foreground; tetap
   berhenti saat background.
4. Komentar sendiri tetap muncul instan; komentar orang lain maks ~5 detik.
5. Tidak ada regresi pada pull-to-dismiss, terminal-state reliability, atau
   surface Postingan selain hilangnya pull-to-refresh.
