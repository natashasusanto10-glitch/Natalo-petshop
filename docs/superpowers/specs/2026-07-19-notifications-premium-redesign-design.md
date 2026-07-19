# Notifikasi — Premium Inset-Grouped Redesign

**Date:** 2026-07-19
**Scope:** `lib/screens/notifications_screen.dart` (+ parsing opsional `imageUrl` di `lib/models/app_notification.dart`)
**Status:** Approved design (mockup #2 premium inset-grouped, dipilih user)

## Problem Statement

Halaman Notifikasi lonceng terasa berantakan:

- Dua timestamp per kartu (relatif "20 jam lalu" DAN absolut "18 Juli 2026 •
  13:18") — redundan.
- Kategori dikodekan dua kali: warna ikon DAN pill teks ("Feed") — dobel.
- Dua ajakan tap: link teks ("Lihat Postingan") DAN chevron ">" — dobel.
- Chrome berat: tiap item kartu ber-border + shadow + radius 22 → kotak dalam
  kotak, layar penuh oleh 4-5 kartu.
- Bobot font ekstrem (judul w900) — tak sejalan skala NataloWeight (body w400 /
  strong w600) yang sudah diadopsi halaman lain.
- Tidak ada thumbnail konten — untuk social commerce, notifikasi kehilangan
  "jembatan balik" visual ke post/produk.

## Design Direction

Gaya **premium inset-grouped** (mockup #2): stream ringan dikelompokkan waktu,
kartu island per grup ala iOS inset-grouped, tab pill menyatu di header biru,
thumbnail konten di kanan tiap baris. Semua memakai token Natalo asli.

### Tokens (WAJIB — tanpa warna/bobot karangan)

- Font: `PlusJakartaSans` (default theme; tidak perlu di-set manual).
- Biru brand: `NataloColors.primary` (#1E5FBF); tint: `NataloColors.primarySoft`
  (#EEF4FF).
- Header hero: `NataloColors.heroTop` + gradient vertikal `heroGradientV`
  (pola halaman hero-biru lain: Akun, Transaksi, Notifikasi lama).
- Status bar: pola `AnnotatedRegion` + strip `ColoredBox(heroTop)` (kontrak
  hero-blue-statusbar yang sudah berlaku; header saat ini sudah benar — jangan
  regresi).
- Bobot font: HANYA w400 (body) dan w600 (strong/judul) — tidak ada w700-w900.
- Warna aksen kategori: pakai warna dari `_NotificationVisual` yang sudah ada
  (ungu Feed, biru pesanan, amber promo, dst.) — dipakai lebih halus (tint
  latar ikon + badge), bukan blok solid.

## Layout Spec

### 1. Header (hero biru)

- Gradient `heroGradientV`, back arrow, judul "Notifikasi" (w600, ~21px,
  putih). Subtitle deskriptif lama DIHAPUS (mengurangi tinggi header).
- Badge counter "N baru" di samping judul: chip kaca
  `Colors.white.withValues(alpha: 0.16)`, teks 11px w600, hanya tampil bila
  ada unread.
- "Tandai dibaca" sebagai TextButton putih-kebiruan di kanan (menggantikan
  ikon centang ganda), memanggil aksi mark-all-read yang sudah ada.

### 2. Tab pill di dalam header

- 4 tab (dari 6): **Semua / Aktivitas / Transaksi / Promo**.
  - Aktivitas = gabungan filter lama Disebut + Feed + Pengumuman.
  - Transaksi = filter lama Pesanan.
  - Promo = tetap.
- Bentuk: pill horizontal-scrollable di bawah judul, MASIH di area gradient
  biru. Aktif = pill putih solid, teks `heroTop`/near-black w600. Non-aktif =
  pill kaca `white alpha 0.12`, teks putih-kebiruan w400.
- Logika pemetaan filter lama → 4 tab dipusatkan di satu fungsi murni supaya
  bisa diuji (mis. `NotificationTabFilter.matches(AppNotification)`).

### 3. Grup waktu

- Bucket: **HARI INI / KEMARIN / MINGGU INI / SEBELUMNYA** berdasarkan
  `createdAt` (hari kalender lokal; "MINGGU INI" = ≤7 hari terakhir di luar
  hari ini/kemarin).
- Label grup: uppercase, 11.5px, w600, warna muted, letter-spacing +0.4,
  padding atas antar grup.
- Fungsi bucketing murni + dapat diuji (mis.
  `notificationTimeBucket(DateTime now, DateTime createdAt)`).

### 4. Kartu island per grup

- Satu `Container` putih (`cs.surface`) per grup: radius 18, shadow sangat
  tipis (`black alpha ~0.06`, blur kecil), margin horizontal 14.
- Baris dipisah hairline 0.5px warna outline lembut, menjorok dari kiri
  (inset ~68px, sejajar teks) — bukan full-width.
- TIDAK ada border/shadow per item lagi.

### 5. Baris notifikasi

Struktur kiri → tengah → kanan:

- **Kiri (identitas):** lingkaran 42px.
  - Notifikasi brand/sistem (feed status, pengumuman): lingkaran
    `NataloColors.primary` berisi "NL" putih w600 — identitas brand.
  - Lainnya: lingkaran tint warna kategori (`visual.color` alpha ~0.12) berisi
    ikon `visual.icon`.
  - Badge kategori opsional 17px di kanan-bawah lingkaran (ikon mini, warna
    kategori, ring putih 2px) — dipakai bila identitas utama adalah avatar
    brand sehingga kategori tetap terbaca.
- **Tengah (satu kalimat + waktu):**
  - Satu teks 13.5px height 1.4: frasa kunci (judul) w600 warna onSurface,
    lanjutan (body dipotong) w400 warna onSurface. Body maks 1 baris lanjutan
    (total blok teks maks 2 baris, ellipsis).
  - Waktu relatif singkat di bawah (11.5px, muted): "20 jam", "1 hari" —
    `formatRelativeTime` yang ada (persingkat bila perlu). Datetime absolut
    DIHAPUS.
  - CTA tonal (hanya bila actionable, dari `_notificationCtaLabel` yang ada):
    pill `primarySoft` bg + teks `primary` 12px w600, sejajar dengan waktu.
    Link teks biru + chevron DIHAPUS; seluruh baris tetap tappable.
- **Kanan (thumbnail, opsional):** 46px, radius 12, `fit: cover`, ring inset
  0.5px (`black alpha 0.08`). Sumber: `imageUrl` baru (lihat Model). Bila
  null → kolom kanan tidak dirender (baris tetap rapi).
- **Unread:** bar aksen 3px `NataloColors.primary` di tepi kiri baris (rounded
  kanan), menggantikan titik pink + border biru. Tanpa tint latar tambahan.

### 6. Model — `imageUrl` opsional (forward-compatible)

- Tambah field `final String? imageUrl` ke `AppNotification` + parsing
  `json['imageUrl'] ?? json['image_url'] ?? json['thumbnailUrl']` +
  ikutkan di `copyWith`.
- Backend BELUM mengirim field ini → semua baris awalnya tampil tanpa
  thumbnail. Setelah rilis app yang memuat parsing ini, begitu backend mulai
  menyertakan URL (follow-up terpisah), thumbnail langsung tampil tanpa
  perubahan client tambahan.
- Pengayaan backend (mengirim thumbnail post/produk) = **out of scope** spec
  ini; dicatat sebagai follow-up.

### 7. Empty state & lainnya

- `_NotificationEmptyState`, pull-to-refresh daftar, pagination/load, logika
  mark-read, dan routing tap TIDAK berubah secara perilaku — hanya restyle
  ringan bila perlu menyesuaikan latar `#EEF2F8`-like (`cs.surfaceContainer`
  atau token abu yang sudah dipakai halaman gray lain).
- Latar halaman: abu lembut konsisten dengan halaman whole-page-gray lain
  (pakai token/warna yang sama dengan Beranda/Katalog gray).

## Out of Scope

- Perubahan backend/payload push (pengiriman `imageUrl`, agregasi sosial
  "X & 3 lainnya").
- Halaman preferensi notifikasi.
- Perubahan deep-link/routing tap (case-case `_handleTap` tetap).
- Dark mode tuning khusus di luar pemakaian token colorScheme yang sudah ada.

## Testing

- Unit: fungsi bucketing waktu (hari ini/kemarin/minggu ini/sebelumnya,
  termasuk tepat tengah malam) dan pemetaan 4 tab (tiap kategori lama jatuh ke
  tab benar; "Semua" memuat semuanya).
- Widget: baris unread menampilkan bar aksen kiri & TANPA titik pink; baris
  dengan `ctaLabel` menampilkan pill tonal; baris tanpa `imageUrl` tidak
  merender slot thumbnail; hanya SATU timestamp (tak ada teks tanggal absolut);
  tidak ada chevron.
- Model: parsing `imageUrl` dari ketiga key + null-safety.
- Regresi: test notifikasi yang ada tetap lulus; `flutter analyze` bersih.
- Device-verify (manual): header/status-bar tetap benar (kontrak hero-blue),
  tab scroll horizontal nyaman, kartu island + hairline terlihat premium di
  layar asli.

## Acceptance Criteria

1. Satu timestamp per baris (relatif); datetime absolut hilang.
2. Kategori terbaca dari identitas kiri (tint/badge) — pill teks kategori
   hilang.
3. Satu ajakan aksi per baris: seluruh baris tappable; CTA tonal hanya untuk
   notifikasi actionable; chevron hilang.
4. Daftar = grup waktu + kartu island; tidak ada lagi border/shadow per item.
5. Tab 4 pill di header biru dengan pemetaan benar (Aktivitas mencakup
   Disebut/Feed/Pengumuman lama).
6. Unread = bar aksen biru kiri + counter "N baru" di header.
7. Semua styling memakai token Natalo (primary/primarySoft/heroTop/
   heroGradientV, w400/w600, PlusJakartaSans); tidak ada w700+.
8. `imageUrl` opsional ter-parse; baris tanpa gambar tetap rapi.
9. Perilaku non-visual (fetch, mark-read, tap routing, pull-refresh) tidak
   berubah.
