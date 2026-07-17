# Typography Weight Scale (Fase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turunkan bobot font ke skala ringan ala IG (Regular 400 + Semibold 600, plus 500 khusus over-media) di surface profil, post detail, dan feed utama, lewat satu token `NataloWeight` — hanya `fontWeight` yang berubah.

**Architecture:** Buat token `lib/theme/natalo_text.dart` (`NataloWeight.body`=w400, `.strong`=w600, `.onMedia`=w500). Ganti literal `FontWeight.wXXX` di call-site pada surface target dengan token sesuai peran. Ukuran/warna/shadow/spacing TIDAK disentuh.

**Tech Stack:** Flutter, Dart.

## Global Constraints

- **HANYA `fontWeight` yang berubah.** Jangan ubah `fontSize`, `color`, `letterSpacing`, `height`, `shadows`, atau struktur widget apa pun.
- **Token tunggal** `NataloWeight` (`body`=FontWeight.w400, `strong`=FontWeight.w600, `onMedia`=FontWeight.w500). Semua penggantian merujuk token, bukan literal baru.
- **Aturan peran → token:**
  - Layar SOLID (profil, post detail non-overlay, sheet, dialog, empty/error state berlatar polos): nama/handle/angka-statistik/harga/judul/tombol/link/badge/inisial-avatar/emphasis-nama/tab-aktif → `strong`; body/caption/bio/label-stat/metadata/tanggal/tab-nonaktif/"N lainnya"/handle-sekunder/empty-body/dialog-body → `body`.
  - OVER-MEDIA (teks di atas video/foto, biasanya putih + shadow atau di pill gelap di atas media): nama/emphasis/tombol → `strong`; caption/body/social-proof → `onMedia`.
- **w700/w800/w900 dihapus total** dari file-file di plan ini. Tidak ada `medium`/w500 di layar solid (hanya `body`/`strong`).
- **Tidak** mengubah `TextTheme` di `natalo_theme.dart`, dan **tidak** menyentuh file di luar daftar plan ini.
- Rail aksi feed (like/comment/share count) sudah w600 — TIDAK ada di scope, jangan diubah.
- Verifikasi tiap task: `flutter analyze <file>` bersih + `grep` memastikan tidak ada `FontWeight.w[789]00` tersisa di file yang digarap task itu.

---

## Task 1: Token `NataloWeight`

**Files:**
- Create: `flutter_app/lib/theme/natalo_text.dart`

**Interfaces:**
- Produces (dipakai semua task berikut): `NataloWeight.body` (FontWeight.w400), `NataloWeight.strong` (FontWeight.w600), `NataloWeight.onMedia` (FontWeight.w500).

- [ ] **Step 1: Buat file token**

```dart
import 'package:flutter/painting.dart' show FontWeight;

/// Skala bobot font tunggal (Fase 2 typography). Ganti literal
/// FontWeight.wXXX yang tersebar supaya hierarki konsisten & ringan ala IG
/// (Regular 400 + Semibold 600). HANYA bobot — ukuran/warna/shadow tetap di
/// call-site.
abstract final class NataloWeight {
  /// Basis: body, label, caption, metadata, bio, label statistik,
  /// tab non-aktif. Layar solid.
  static const body = FontWeight.w400;

  /// Hierarki: nama/handle, angka statistik, judul, tombol, link, badge,
  /// inisial avatar, emphasis nama inline, tab aktif. Berlaku juga untuk
  /// nama/emphasis DI ATAS media.
  static const strong = FontWeight.w600;

  /// HANYA body/caption/social-proof DI ATAS media (feed imersif + overlay
  /// author video). Floor lebih tinggi dari `body` supaya teks putih di atas
  /// video tetap terbaca.
  static const onMedia = FontWeight.w500;
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/theme/natalo_text.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/theme/natalo_text.dart
git commit -m "feat(theme): token NataloWeight (skala bobot font Fase 2)"
```

---

## Task 2: Terapkan di surface Profil

**Files (semua Modify):**
- `flutter_app/lib/screens/member_screen.dart`
- `flutter_app/lib/screens/member_posts_screen.dart`
- `flutter_app/lib/widgets/public_profile_content_tab_bar.dart`
- `flutter_app/lib/widgets/public_profile_expanded_header.dart`
- `flutter_app/lib/widgets/public_profile_chrome_overlay.dart`
- `flutter_app/lib/widgets/public_profile_mutual_followers_row.dart`
- `flutter_app/lib/screens/public_profile_screen.dart`
- `flutter_app/lib/screens/public_profile_follow_list_screen.dart`

**Interfaces:**
- Consumes: `NataloWeight` dari `../theme/natalo_text.dart` (sesuaikan path relatif: dari `lib/screens/` → `../theme/natalo_text.dart`; dari `lib/widgets/` → `../theme/natalo_text.dart`).

Semua ini surface SOLID (kecuali dua nama overlay di chrome_overlay yang tetap `strong`). Tambah `import '../theme/natalo_text.dart';` di tiap file yang belum punya.

- [ ] **Step 1: Ganti per baris (member_screen.dart)**

Nomor baris adalah acuan audit; kalau bergeser, cari berdasarkan konteks peran. Ganti nilai `fontWeight:` menjadi token:

| Line | Peran | Dari | Ke |
|---|---|---|---|
| 593 | nama profil | w800 | `NataloWeight.strong` |
| 662 | header "Draft (N)" | w900 | `NataloWeight.strong` |
| 803 | metadata thumbnail | w700 | `NataloWeight.body` |
| 841 | badge label di atas media | w800 | `NataloWeight.strong` |
| 1109 | style pill badge | w900 | `NataloWeight.strong` |
| 1157 | empty-state title | w900 | `NataloWeight.strong` |
| 1167 | empty-state body | w600 | `NataloWeight.body` |
| 1185 | tombol "Buat Postingan" | w900 | `NataloWeight.strong` |
| 1206 | empty-state per-filter | w700 | `NataloWeight.body` |
| 1306 | counter carousel | w900 | `NataloWeight.strong` |
| 1499 | error overlay | w800 | `NataloWeight.strong` |

- [ ] **Step 2: Ganti per baris (file profil lain)**

`member_posts_screen.dart`: L249 label kecil w600 → `NataloWeight.body`.

`public_profile_content_tab_bar.dart`: L111 labelStyle tab aktif w800 → `NataloWeight.strong`; L115 unselectedLabelStyle w700 → `NataloWeight.body`.

`public_profile_expanded_header.dart`: L151 nama w800 → `strong`; L227 badge "AKUN RESMI" w700 → `strong`; L319 angka statistik w800 → `strong`; L331 label statistik w600 → `body`; L519 label pill/tombol w800 → `strong`.

`public_profile_chrome_overlay.dart`: L196 nama brand w700 → `strong`; L223 handle w700 → `strong`.

`public_profile_mutual_followers_row.dart`: L67 body "mutual" w500 → `body`; L72 nama emphasis w700 → `strong`.

`public_profile_screen.dart`: L1130 badge jumlah produk w600 → `strong`; L1157 label harga w600 → `strong`; L1279 body w500 → `body`; L1331 empty-state title w800 → `strong`; L1367 "User tidak ditemukan" title w900 → `strong`; L1377 body w600 → `body`.

`public_profile_follow_list_screen.dart`: L90 handle header w800 → `strong`; L111 tab aktif w800 → `strong`; L115 tab non-aktif w700 → `body`; L506 nama user w800 → `strong`; L527 handle sekunder w600 → `body`; L547 tombol "Follow" w800 → `strong`; L573 tombol "Following" w800 → `strong`; L688 judul/empty-state w800 → `strong`.

**Aturan untuk situs `fontWeight` lain di file-file ini yang tidak tercantum di tabel:** kalau ada kemunculan `FontWeight.w700/w800/w900` yang terlewat di file-file profil ini, klasifikasikan dengan aturan Global Constraints (nama/angka/judul/tombol/badge/link → `strong`; sisanya → `body`) dan ganti juga. Setelah selesai, TIDAK boleh ada `FontWeight.w700/w800/w900` tersisa di kedelapan file ini.

- [ ] **Step 3: Analyze + grep verifikasi**

Run: `flutter analyze lib/screens/member_screen.dart lib/screens/member_posts_screen.dart lib/widgets/public_profile_content_tab_bar.dart lib/widgets/public_profile_expanded_header.dart lib/widgets/public_profile_chrome_overlay.dart lib/widgets/public_profile_mutual_followers_row.dart lib/screens/public_profile_screen.dart lib/screens/public_profile_follow_list_screen.dart`
Expected: No issues found.

Run: `grep -rn "FontWeight.w[789]00" lib/screens/member_screen.dart lib/screens/member_posts_screen.dart lib/widgets/public_profile_content_tab_bar.dart lib/widgets/public_profile_expanded_header.dart lib/widgets/public_profile_chrome_overlay.dart lib/widgets/public_profile_mutual_followers_row.dart lib/screens/public_profile_screen.dart lib/screens/public_profile_follow_list_screen.dart`
Expected: tidak ada output (0 sisa).

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/screens/member_screen.dart flutter_app/lib/screens/member_posts_screen.dart flutter_app/lib/widgets/public_profile_content_tab_bar.dart flutter_app/lib/widgets/public_profile_expanded_header.dart flutter_app/lib/widgets/public_profile_chrome_overlay.dart flutter_app/lib/widgets/public_profile_mutual_followers_row.dart flutter_app/lib/screens/public_profile_screen.dart flutter_app/lib/screens/public_profile_follow_list_screen.dart
git commit -m "polish(profile): turunkan bobot font ke skala NataloWeight (ala IG)"
```

---

## Task 3: Terapkan di Post Detail

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`

**Interfaces:**
- Consumes: `NataloWeight` dari `../theme/natalo_text.dart`.

Tambah `import '../theme/natalo_text.dart';`. Sebagian besar SOLID; DUA overlay author video + error video = OVER-MEDIA.

- [ ] **Step 1: Ganti per baris**

| Line | Peran | Konteks | Dari | Ke |
|---|---|---|---|---|
| 803 | judul "Postingan" | solid | w800 | `strong` |
| 822 | status/nama official | solid | w700 | `strong` bila nama/handle, `body` bila label status (baca call-site) |
| 843 | empty-state | solid | w700 | `body` |
| 1577 | label tanggal | solid | w700 | `body` |
| 1636 | nama author (overlay terang) | OVER-MEDIA | w700 | `strong` |
| 1722 | nama author (overlay gelap) | OVER-MEDIA | w700 | `strong` |
| 1882 | `_LikedByLine` nama emphasis | solid | w900 | `strong` |
| 1889 | `_LikedByLine` "N lainnya" | solid | w900 | `strong` |
| 1900 | `_LikedByLine` sisa body | solid | w600 | `body` |
| 2030 | inisial avatar | solid | w900 | `strong` |
| 2087 | `PostCaption` body | solid | w600 | `body` |
| 2100 | prefix nama di caption | solid | w900 | `strong` |
| 2149 | prefix nama di caption | solid | w900 | `strong` |
| 2158 | "selengkapnya" | solid | w800 | `strong` |
| 2206 | badge produk tag | solid | w900 | `strong` |
| 2218 | deskripsi produk tag | solid | w700 | `body` |
| 2402 | counter carousel | solid | w800 | `strong` |
| 2984 | pesan error video | OVER-MEDIA | w700 | `onMedia` |
| 3018 | tombol "Coba lagi" | OVER-MEDIA | w700 | `strong` |
| 3093 | menu "Edit caption" | solid | w800 | `strong` |
| 3108 | menu "Hapus postingan" | solid | w800 | `strong` |
| 3162 | judul dialog | solid | w900 | `strong` |
| 3172 | body dialog | solid | w600 | `body` |
| 3213 | tombol "Batal" | solid | w800 | `strong` |
| 3235 | tombol "Simpan" | solid | w800 | `strong` |

**Aturan sisa:** kalau ada `FontWeight.w700/w800/w900` lain di file ini yang terlewat, klasifikasikan dgn Global Constraints. Setelah selesai tidak boleh ada w700/w800/w900 tersisa di file ini.

- [ ] **Step 2: Analyze + grep**

Run: `flutter analyze lib/screens/member_post_detail_screen.dart`
Expected: No issues found.

Run: `grep -n "FontWeight.w[789]00" lib/screens/member_post_detail_screen.dart`
Expected: tidak ada output.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart
git commit -m "polish(postingan): turunkan bobot font post detail ke skala NataloWeight"
```

---

## Task 4: Terapkan di Feed utama

**Files (semua Modify):**
- `flutter_app/lib/screens/feed_screen.dart`
- `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- `flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart`

**Interfaces:**
- Consumes: `NataloWeight`. Path dari `lib/screens/` → `../theme/natalo_text.dart`; dari `lib/features/feed/widgets/` → `../../../theme/natalo_text.dart`.

Tambah import di tiap file. Empty/error state feed = latar polos gelap → perlakukan SOLID. Social-proof + retry pill + badge overlay = OVER-MEDIA/badge.

- [ ] **Step 1: Ganti per baris**

`feed_screen.dart`:
| Line | Peran | Konteks | Dari | Ke |
|---|---|---|---|---|
| 1382 | badge count notif | badge (container solid) | w900 | `strong` |
| 1538 | empty-state title | solid (latar gelap polos) | w900 | `strong` |
| 1548 | empty-state body | solid | w600 | `body` |
| 1595 | error-state title | solid | w900 | `strong` |
| 1605 | error message | solid | w600 | `body` |
| 1620 | tombol "Coba lagi" | solid | w900 | `strong` |

`feed_video_post_view.dart`:
| Line | Peran | Konteks | Dari | Ke |
|---|---|---|---|---|
| 3816 | tombol "Coba lagi" (pill di atas video) | OVER-MEDIA | w800 | `strong` |

`feed_post_shared_widgets.dart` (`FeedPostSocialProof`, semua OVER-MEDIA):
| Line | Peran | Dari | Ke |
|---|---|---|---|
| 69 | nama liker utama | w800 | `strong` |
| 75 | "N orang lainnya" | w800 | `strong` |
| 85 | style dasar social-proof (body) | w500 | `onMedia` |
| 142 | inisial avatar | w800 | `strong` |

**Aturan sisa:** kalau ada `FontWeight.w700/w800/w900` lain yang terlewat di ketiga file feed ini, klasifikasikan dgn Global Constraints + konteks over-media vs solid. Setelah selesai tidak boleh ada w700/w800/w900 tersisa di ketiga file ini. (`feed_post_shared_widgets.dart` L85 sudah w500 → jadi `onMedia`; itu bukan w7/8/900 tapi tetap ditokenkan agar konsisten.)

- [ ] **Step 2: Analyze + grep**

Run: `flutter analyze lib/screens/feed_screen.dart lib/features/feed/widgets/feed_video_post_view.dart lib/features/feed/widgets/feed_post_shared_widgets.dart`
Expected: No issues found.

Run: `grep -n "FontWeight.w[789]00" lib/screens/feed_screen.dart lib/features/feed/widgets/feed_video_post_view.dart lib/features/feed/widgets/feed_post_shared_widgets.dart`
Expected: tidak ada output.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart
git commit -m "polish(feed): turunkan bobot font ke skala NataloWeight (over-media w500/w600)"
```

---

## Task 5: Verifikasi menyeluruh

**Files:** tidak ada perubahan kode (kecuali perbaikan kecil bila ada temuan).

- [ ] **Step 1: Analyze seluruh lib**

Run: `flutter analyze lib/`
Expected: Tidak ada issue BARU dibanding baseline (baseline: 3 info `use_key_in_widget_constructors` di `feed_post_shared_widgets.dart` yang sudah ada sebelumnya — abaikan bila masih muncul, tapi jangan tambah baru).

- [ ] **Step 2: Jalankan test yang menyentuh surface terdampak**

Run: `flutter test test/feed_action_rail_test.dart test/feed_post_preview_screen_test.dart`
Expected: PASS (memastikan tak ada regresi kompilasi di sekitar feed). Jika ada test lain yang gagal karena assertion `fontWeight`, periksa: bila assertion itu meng-hardcode bobot lama, update ke token baru; bila bukan terkait, catat sebagai pre-existing.

- [ ] **Step 3: Grep global sisa (di scope plan)**

Run: `grep -rn "FontWeight.w[789]00" lib/screens/member_screen.dart lib/screens/member_posts_screen.dart lib/widgets/public_profile_content_tab_bar.dart lib/widgets/public_profile_expanded_header.dart lib/widgets/public_profile_chrome_overlay.dart lib/widgets/public_profile_mutual_followers_row.dart lib/screens/public_profile_screen.dart lib/screens/public_profile_follow_list_screen.dart lib/screens/member_post_detail_screen.dart lib/screens/feed_screen.dart lib/features/feed/widgets/feed_video_post_view.dart lib/features/feed/widgets/feed_post_shared_widgets.dart`
Expected: 0 output.

- [ ] **Step 4: Commit (bila ada penyesuaian)**

Bila Step 1-3 memicu perbaikan, commit `test(typography): stabilkan verifikasi`. Bila tidak, lewati.

## Catatan device-verify (di luar plan otomatis)

Tak ada golden test → WAJIB device-verify visual iOS + Android setelah merge: cek profil (nama/angka/label statistik/tombol), post detail (caption, "Disukai oleh", judul, dialog edit), feed imersif (nama author + caption over-video masih terbaca dengan w600/w500), dan empty/error state feed. Pastikan tidak ada teks yang jadi terlalu tipis/sulit dibaca di atas media.
