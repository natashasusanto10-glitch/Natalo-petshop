# Design — Polish tab bar & header profil

Tanggal: 2026-07-17
Status: Disetujui (menunggu review spec)

Spec terpisah dari `2026-07-17-post-detail-video-double-tap-like-design.md`. Fokus: permukaan header/tab profil (profil publik + tab Akun).

## Masalah

Pada halaman profil (profil publik `PublicProfileScreen` maupun tab Akun `MemberScreen`), tab konten Postingan/Video/Belanja punya tiga masalah visual:

1. **Gap terlalu jauh antara baris tombol dan tab.** Terukur ~45px ruang kosong mati untuk akun official (bio 1 baris, tanpa mutual): `PublicProfileHeaderMetrics.resolve` mengalokasikan `identityHeight = 256.8px` padahal konten header hanya 212px. Formula `_identityHeight` meng-over-reserve (mengasumsikan bio 2 baris + slack). Terlihat seperti area Story Highlights kosong — padahal app tidak punya fitur itu.

2. **Garis panjang di bawah pill tab.** `PublicProfileContentTabBar` memakai `TabBar` Material 3 tanpa menyetel `dividerColor`/`dividerHeight`, sehingga Flutter menggambar divider full-width default di bawah tab. Pill aktif menutupi sebagiannya sehingga terlihat sebagai garis panjang mengganggu. Muncul di semua halaman profil.

3. **Indikator tab aktif "snap".** Garis indikator pendek (`Key('public_tab_expanded_underline')`) di `_PublicProfileTab` hanya dirender saat `emphasis > 0.5` dan diposisikan di tengah tiap tab — jadi hilang-lalu-muncul (snap) saat pindah tab alih-alih menggeser mulus.

## Tujuan

1. Rapatkan gap tab agar ≈ konten (tab duduk dekat baris tombol, jarak nafas kecil ala IG), tanpa risiko clipping saat bio 2 baris / text-scale besar.
2. Hilangkan garis panjang divider TabBar di semua halaman profil.
3. Indikator tab aktif menggeser mulus mengikuti animasi controller saat pindah tab.

## Non-tujuan

- Tidak menambah `@username` di header profil publik official (diputuskan tidak perlu — username di top bar tab Akun sudah cukup).
- Tidak mengubah username brand di DB.
- Tidak mengubah layout stats/avatar/tombol.

## Pendekatan

Semua tab bar profil kini memakai `PublicProfileContentTabBar` (tab bar lama `ProfileContentTabBar` sudah tak dipakai setelah redesign Akun), sehingga perbaikan #2 dan #3 cukup di satu tempat.

### 1. Rapatkan gap — `lib/widgets/public_profile_chrome_overlay.dart`

Perkecil over-reservation di `PublicProfileHeaderMetrics._identityHeight`:

- Ukur jumlah baris bio sebenarnya pada lebar layar via `TextPainter` (bukan asumsi tetap 2 baris), lalu reserve sesuai baris aktual (maks 2, sesuai `maxLines` header).
- Pangkas slack konstanta lain (safety, per-baris) agar `identityHeight` ≈ tinggi konten + margin bawah wajar.
- Verifikasi lewat pengukuran (test sementara) bahwa selisih `identityHeight − konten` turun ke ambang kecil (target ≤ ~12px) untuk kasus: official 1-baris-bio, regular 1-baris, regular 2-baris, dengan/ tanpa mutual, di text-scale 1.0 dan 1.3 — tanpa membuat konten ter-clip (selisih tidak boleh negatif).

Catatan: `identityHeight` dipakai oleh chrome overlay untuk `scrollSpaceHeight`, `tabTop`, dan choreografi collapse — jadi nilainya tetap deterministik (pure), hanya lebih akurat.

### 2. Hapus divider panjang — `lib/widgets/public_profile_content_tab_bar.dart`

Set `dividerColor: Colors.transparent` (dan/atau `dividerHeight: 0`) pada `TabBar`. Berlaku otomatis untuk profil publik + tab Akun.

### 3. Indikator geser mulus — `lib/widgets/public_profile_content_tab_bar.dart`

Ganti indikator per-tab yang di-gate `emphasis > 0.5` dengan indikator tunggal yang **menggeser** posisinya mengikuti `controller.animation` (interpolasi antara pusat tab-i dan tab-(i+1)). Lebar indikator tetap kecil (~24px), opacity mengikuti `underlineOpacity` (tetap 0 saat fully collapsed di profil publik; tetap 1 di tab Akun yang selalu expanded). Saat swipe/tap antar tab, indikator meluncur mulus tanpa hilang-muncul.

### 4. (Bonus) Hapus dead code

Hapus `ProfileContentTabBar`, `_AnimatedProfileTab`, dan `ProfileContentTabHeaderDelegate` di `lib/widgets/profile_content_tab_bar.dart` (sudah tak dipakai) beserta `test/widgets/profile_content_tab_bar_test.dart`. Konfirmasi via grep tidak ada referensi tersisa sebelum menghapus.

## Testing

- **Gap**: test pengukuran (boleh throwaway) memastikan `identityHeight − kontenHeight` ≤ ambang kecil dan ≥ 0 untuk matriks kasus di atas. Golden profil publik + Akun diregenerasi sebagai bukti visual jarak yang rapat.
- **Divider**: widget test memastikan tidak ada divider TabBar yang terlihat (mis. `TabBar.dividerColor == Colors.transparent`, atau tidak ada garis full-width di bawah baris tab).
- **Indikator mulus**: widget test menggerakkan `TabController.animation` ke nilai antara (mis. 0.5) dan memastikan posisi indikator berada di antara dua tab (bukan snap ke salah satu). Semantics `selected` tetap benar.
- Regresi: seluruh test profil (`public_profile_*`, `member_screen_*`) + golden tetap hijau.

## Yang tidak berubah

Layout avatar/stats/tombol, chrome Liquid Glass, perilaku follow, grid, dan konten tab. Perubahan murni pada tinggi header (lebih akurat), divider TabBar, dan gaya indikator.
