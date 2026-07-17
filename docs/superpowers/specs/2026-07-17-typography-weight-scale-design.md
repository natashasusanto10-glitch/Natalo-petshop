# Design — Typography weight scale (Fase 2): profil + post detail + feed

Tanggal: 2026-07-17
Status: Disetujui (menunggu review spec)

## Masalah

App memakai bobot font sangat berat hampir di mana-mana. Hitung `FontWeight` app-wide:

- w900 ×466, w800 ×242, w700 ×264 (total berat: 972)
- w600 ×195, w500 ×56, **w400 ×5**

Akibatnya hierarki visual rata — saat semua tebal, tidak ada yang menonjol, dan kesan keseluruhan "berat/murah" dibanding IG yang "bersih/premium". Instagram pada dasarnya sistem **dua-bobot** di layar solid: Regular (400) sebagai basis + Semibold (~600) untuk hierarki; Bold penuh jarang. (Divalidasi terhadap konvensi IG + screenshot referензi profil IG.)

Ada `TextTheme` pusat di `lib/theme/natalo_theme.dart`, tapi bobotnya juga berat (display w800, title w700) dan mayoritas layar meng-override dengan `fontWeight` inline — jadi theme praktis tidak mengatur typography. Tidak ada file token teks bersama lain.

## Tujuan

Turunkan bobot font ke skala ringan ala IG di tiga surface — **profil, halaman post detail, dan feed utama** — lewat satu sumber kebenaran (token), tanpa mengubah ukuran/warna/shadow.

## Non-tujuan

- **Tidak** mengubah ukuran font, warna, letter-spacing, atau shadow — HANYA `fontWeight`.
- **Tidak** menyentuh surface di luar tiga surface ini (katalog, keranjang, checkout, beranda, admin, dll.) — fase lanjutan terpisah.
- **Tidak** mengubah `TextTheme` pusat di `natalo_theme.dart` (menghindari efek app-wide tak terkontrol). Token baru dipakai eksplisit di surface target saja.
- **Tidak** merefactor dua implementasi "Disukai oleh" jadi satu (di luar scope; masing-masing tetap terpisah, hanya bobotnya disamakan lewat skala).

## Skala bobot

Token baru `lib/theme/natalo_text.dart`:

```dart
import 'package:flutter/painting.dart' show FontWeight;

/// Skala bobot font tunggal (Fase 2 typography). Ganti literal
/// FontWeight.wXXX yang tersebar supaya hierarki konsisten & ringan ala IG.
/// HANYA bobot — ukuran/warna/shadow tetap di call-site.
abstract final class NataloWeight {
  /// Basis: body, label, caption, metadata, bio, label statistik,
  /// tab non-aktif. Layar solid.
  static const body = FontWeight.w400;

  /// Hierarki: nama/handle, angka statistik, judul section, tombol, link,
  /// badge, inisial avatar, emphasis nama inline, tab aktif. Berlaku juga
  /// untuk nama/emphasis DI ATAS media.
  static const strong = FontWeight.w600;

  /// HANYA body/caption/social-proof DI ATAS media (feed imersif + overlay
  /// author video). Floor lebih tinggi dari `body` supaya teks putih di atas
  /// video tetap terbaca (app pakai text-shadow, bukan scrim penuh).
  static const onMedia = FontWeight.w500;
}
```

### Peran → token (layar solid: profil, post detail, sheet, dialog)

| Peran | Sekarang (contoh) | Token |
|---|---|---|
| Nama/handle, display name | w800/w900 | `strong` (w600) |
| Angka statistik (jumlah follower/post) | w800 | `strong` (w600) |
| Label statistik ("Pengikut", "Postingan") | w600 | `body` (w400) |
| Judul section, empty-state title, judul dialog | w900 | `strong` (w600) |
| Tombol (Follow/Following/Simpan/Batal/Buat Postingan) | w800/w900 | `strong` (w600) |
| Link/aksi teks ("selengkapnya"), item menu bottom-sheet | w800 | `strong` (w600) |
| Badge (AKUN RESMI, style pill, diskon, index carousel) | w900 | `strong` (w600) |
| Inisial avatar fallback | w900 | `strong` (w600) |
| Emphasis nama inline (dalam kalimat "Disukai oleh…", prefix caption) | w900 | `strong` (w600) |
| Tab aktif (labelStyle) | w800 | `strong` (w600) |
| Body, caption, bio, metadata/tanggal, empty-state body, dialog body | w600/w700 | `body` (w400) |
| Tab non-aktif (unselectedLabelStyle) | w700 | `body` (w400) |
| "N orang lainnya" / handle sekunder | w700 | `body` (w400) |

Catatan: w500 (`medium`) SENGAJA TIDAK dipakai di layar solid — mengikuti IG yang murni dua-bobot (Regular + Semibold). Sekunder/others turun ke `body` (w400).

### Peran → token (DI ATAS media: feed imersif + overlay author video di post detail)

| Peran | Token |
|---|---|
| Nama/handle author, emphasis, tombol | `strong` (w600) |
| Caption / body / social-proof di atas media | `onMedia` (w500) |
| Pesan error video + tombol "Coba lagi" (over media) | `onMedia` (w500) untuk body, `strong` (w600) untuk tombol |

## Surface & inventaris

Semua nilai `fontWeight` di bawah adalah literal inline (bukan referensi token). Ganti ke `NataloWeight.*` sesuai peran di atas.

### A. Profil (skala layar-solid)

- `lib/screens/member_screen.dart` — L593 nama (w800→strong); L662 header "Draft (N)" (w900→strong); L803 metadata kecil thumbnail (w700→body); L841 badge di atas media (w800→**strong**, ini badge di atas media tapi label pendek → strong); L1109 style pill badge (w900→strong); L1157 empty-state title (w900→strong); L1167 empty-state body (w600→body); L1185 tombol "Buat Postingan" (w900→strong); L1206 empty-state per-filter (w700→body); L1306 counter carousel (w900→strong); L1499 error overlay (w800→strong).
- `lib/screens/member_posts_screen.dart` — L249 label kecil (w600→body).
- `lib/widgets/public_profile_content_tab_bar.dart` — L111 labelStyle tab aktif (w800→strong); L115 unselected (w700→body).
- `lib/widgets/public_profile_expanded_header.dart` — L151 nama (w800→strong); L227 badge "AKUN RESMI" (w700→strong); L319 angka statistik (w800→strong); L331 label statistik (w600→body); L519 label pill/tombol (w800→strong).
- `lib/widgets/public_profile_chrome_overlay.dart` — L196 nama brand (w700→strong); L223 handle (w700→strong).
- `lib/widgets/public_profile_mutual_followers_row.dart` — L67 body "mutual" (w500→body); L72 nama emphasis (w700→strong).
- `lib/screens/public_profile_screen.dart` — L1130 badge jumlah produk (w600→strong, badge); L1157 label harga (w600→strong, angka/harga = emphasis); L1279 body (w500→body); L1331 empty-state title (w800→strong); L1367 "User tidak ditemukan" title (w900→strong); L1377 body (w600→body).
- `lib/screens/public_profile_follow_list_screen.dart` — L90 handle header (w800→strong); L111 tab aktif (w800→strong); L115 tab non-aktif (w700→body); L506 nama user (w800→strong); L527 handle sekunder (w600→body); L547 tombol "Follow" (w800→strong); L573 tombol "Following" (w800→strong); L688 judul/empty-state (w800→strong).

### B. Post detail (skala layar-solid, kecuali overlay author video = over-media)

- `lib/screens/member_post_detail_screen.dart`:
  - L803 judul "Postingan" (w800→strong); L822 status official (w700→body metadata, atau strong bila itu nama — cek call-site: bila nama/handle → strong, bila label status → body); L843 empty-state (w700→body); L1577 label tanggal (w700→body).
  - Overlay author di atas video: L1636 nama (over-media, w700→**strong**); L1722 nama overlay gelap (over-media, w700→**strong**).
  - `_LikedByLine` (lokal, layar solid): L1882/L1889 nama & "N lainnya" emphasis (w900→strong); L1900 sisa body (w600→body).
  - L2030 inisial avatar (w900→strong).
  - `PostCaption` (lokal, layar solid): L2087 body caption (w600→body); L2100/L2149 prefix nama pemilik (w900→strong); L2158 "selengkapnya" (w800→strong).
  - Produk tag: L2206 badge (w900→strong); L2218 deskripsi produk (w700→body).
  - L2402 counter carousel (w800→strong).
  - Error video (over media): L2984 pesan (w700→onMedia); L3018 tombol "Coba lagi" (w700→strong).
  - Menu bottom-sheet & dialog (layar solid): L3093 "Edit caption" (w800→strong); L3108 "Hapus postingan" (w800→strong); L3162 judul dialog (w900→strong); L3172 body dialog (w600→body); L3213 "Batal" (w800→strong); L3235 "Simpan" (w800→strong).

### C. Feed utama (skala over-media untuk teks di atas video/foto)

- `lib/features/feed/widgets/feed_post_shared_widgets.dart` — `FeedPostSocialProof`: L69 nama primer (w800→strong); L75 "N lainnya" (w800→strong emphasis, atau onMedia bila diperlakukan sbg body — pakai strong utk nama, onMedia utk kata sambung); L85 sisa body (w500→onMedia, tetap); L142 inisial avatar (w800→strong). Plus audit tambahan saat planning: `FeedPostCreatorIdentity` (nama author over-media → strong) dan teks lain di file ini.
- `lib/screens/feed_screen.dart` — inventaris `fontWeight` belum dipetakan penuh di audit ini; WAJIB dipetakan line-level saat penulisan plan. Aturan: teks di atas media → nama/emphasis `strong`, body/caption `onMedia`; teks di sheet/panel solid → skala layar-solid.
- `lib/features/feed/widgets/feed_video_post_view.dart` — sama; inventaris line-level dipetakan saat planning. (Rail aksi sudah w600 = konsisten, tidak diubah.)

## Kasus khusus / keputusan

- **Badge kecil** (AKUN RESMI, style pill, diskon, jumlah produk, harga): pakai `strong` (w600), bukan diturunkan ke body — tetap terbaca di ukuran kecil, sejalan IG (label kecil = semibold).
- **Inisial avatar fallback**: `strong` (w600) — dekоratif, w900 terlalu berat.
- **Angka/harga**: diperlakukan sebagai emphasis → `strong`.
- **Rail aksi feed** (like/comment/share count) sudah w600 → biarkan, sudah sesuai.
- **Dua implementasi "Disukai oleh"** (`_LikedByLine` post-detail w900 vs `FeedPostSocialProof` feed w800) diselaraskan lewat skala yang sama (nama→strong, body→body/onMedia) tapi tetap dua file terpisah.
- Ambiguitas peran per call-site (mis. L822 status vs nama) diputuskan implementer dengan membaca konteks: **nama/handle/angka/judul/tombol/badge/link → strong; sisanya → body (solid) atau onMedia (over media)**.

## Verifikasi

- Tidak ada golden test di repo → verifikasi via `flutter analyze` (bersih) + review adversarial per-surface + device-verify visual iOS/Android.
- Eksekusi via subagent-driven development: task per grup surface (token → profil → post detail → feed → verifikasi), review spec+quality tiap task.

## Ringkasan file

- Baru: `lib/theme/natalo_text.dart` (`NataloWeight`).
- Modifikasi (profil): member_screen, member_posts_screen, public_profile_content_tab_bar, public_profile_expanded_header, public_profile_chrome_overlay, public_profile_mutual_followers_row, public_profile_screen, public_profile_follow_list_screen.
- Modifikasi (post detail): member_post_detail_screen.
- Modifikasi (feed): feed_post_shared_widgets, feed_screen, feed_video_post_view.
