# Popup Pembuka Aplikasi (Launch Promo/Announcement Popup)

- **Tanggal:** 2026-07-07
- **Status:** Design disetujui — menunggu review spec sebelum implementasi
- **Surface:** Flutter mobile app (`flutter_app/`)
- **Referensi visual:** contoh ROXIT (poster promo saat buka app) → diadaptasi ke token Natalo, gaya "Hybrid"

## 1. Konteks & tujuan

Saat user membuka aplikasi, tampilkan satu popup di atas Beranda untuk mengumumkan
promo atau pengumuman toko. Tujuannya menaikkan awareness campaign (mis. diskon,
produk unggulan) tanpa mengganggu alur yang lebih penting (notifikasi, deep-link).

Versi pertama sengaja **sederhana dan cepat rilis**: konten di-hardcode untuk satu
campaign, tapi dirancang dengan "sekat bersih" supaya nanti tinggal ganti sumbernya
ke API (admin-managed dari website) tanpa membongkar UI atau logika gate.

## 2. Keputusan yang sudah disepakati

| Aspek | Keputusan |
|---|---|
| Isi | Campuran: **promo** (nada merah) atau **pengumuman** (nada hijau) |
| Sumber konten | **Hardcoded** 1 campaign dulu; siap upgrade ke API |
| Frekuensi | Setiap **cold start** (tanpa opsi "jangan tampilkan lagi") |
| Arti "buka app" | **Cold start saja** (bukan resume dari background) |
| Gaya visual | **Hybrid** — gambar atas opsional + judul + teks singkat + tombol |
| Tombol utama | Membuka **satu produk spesifik** |
| Skip bila | (a) dibuka via notif/deep-link, (b) masih onboarding, (c) offline, (d) **belum login (member-only)** |

## 3. Non-goals (YAGNI — di luar cakupan v1)

- Tidak ada admin UI / endpoint API untuk mengelola popup (menyusul, lihat §11).
- Tidak ada carousel banyak popup sekaligus (contoh ROXIT punya deretan promo — v1 satu konten saja).
- Tidak ada penjadwalan mulai/selesai dari server, A/B test, atau targeting segmen.
- Tidak ada opsi user "jangan tampilkan lagi" / frequency cap (konsekuensi dari pilihan "tiap cold start").
- Tidak ada perubahan pada website Next.js.

## 4. Arsitektur & prinsip

Dua ide inti:

1. **Gate di rantai builder `main.dart`** — sebuah widget `LaunchPromoGate`
   disisipkan sejajar `ReadOnlyWelcomeGate`, mengikuti pola gate yang sudah ada
   (`AppStartupSplash → AppLockGate → ReadOnlyWelcomeGate`). Gate mengevaluasi
   kondisi sekali per proses lalu menampilkan popup lewat `showGeneralDialog`
   pada `rootNavigatorKey`.

   > **Kenapa bukan `HomeScreen.initState`?** Route `/` di-push ulang tiap ganti
   > tab (`pushNamedAndRemoveUntil` di bottom nav), jadi `initState` Home akan
   > terpicu berkali-kali — bukan hanya cold start. Gate + penanda "sudah tampil
   > di proses ini" memberi semantik **sekali per cold start** yang benar.

2. **Sekat bersih (clean seam)** — gate & UI hanya bergantung pada satu fungsi
   penyedia konten `activeLaunchPopup()` yang mengembalikan `LaunchPopupCampaign?`.
   Saat ini isinya hardcoded; kelak diganti fetch API. Gate/UI tidak tahu (dan
   tidak peduli) dari mana datanya.

Diagram alur singkat:

```
main() ──▶ MaterialApp.builder
             └─ AppStartupSplash
                └─ AppLockGate
                   └─ ReadOnlyWelcomeGate
                      └─ LaunchPromoGate   ◀── BARU
                         └─ (Stack: child + OfflineBanner)
```

## 5. Komponen (unit & batas tanggung jawab)

Setiap unit punya satu tujuan, antarmuka jelas, dan bisa dites terpisah.

### 5.1 `models/launch_popup_campaign.dart` (baru)
Model data murni untuk satu konten popup.

```dart
enum LaunchPopupTone { promo, announcement } // merah / hijau

class LaunchPopupCampaign {
  final String id;            // penanda campaign (mis. 'promo-juli-2026')
  final LaunchPopupTone tone; // menentukan warna chip/aksen
  final String? imageUrl;     // hero opsional (asset path ATAU URL). null = mode teks
  final String title;
  final String body;
  final String categoryLabel; // teks chip, mis. 'Promo' / 'Pengumuman'
  final String? ctaLabel;     // mis. 'Lihat produk'. null = sembunyikan tombol utama
  final String? ctaHref;      // mis. '/produk/royal-canin-kitten' → deepLinkService
  final String dismissLabel;  // mis. 'Nanti saja'
}
```
- **Dependensi:** tidak ada (model murni). **Konsumen:** provider + gate + dialog.

### 5.2 `config/launch_popup_campaigns.dart` (baru) — *sekat bersih*
Sumber konten hardcoded + fungsi seleksi.

```dart
/// Kembalikan campaign yang aktif untuk ditampilkan, atau null kalau tidak ada.
/// V1: hardcoded. Upgrade ke API cukup ganti isi fungsi ini (lihat §11).
LaunchPopupCampaign? activeLaunchPopup() => _campaign;

const _campaign = LaunchPopupCampaign(
  id: 'promo-juli-2026',
  tone: LaunchPopupTone.promo,
  imageUrl: null, // v1 bisa mulai tanpa gambar; isi asset/URL saat siap
  title: 'Diskon 30% khusus member',
  body: 'Hemat 30% untuk vitamin dan makanan. Berlaku sampai 13 Juli.',
  categoryLabel: 'Promo',
  ctaLabel: 'Lihat produk',
  ctaHref: '/produk/<slug-produk-unggulan>',
  dismissLabel: 'Nanti saja',
);
```
- **Dependensi:** hanya model. **Konsumen:** gate.
- Set `_campaign` ke `null` untuk mematikan popup tanpa hapus kode.

### 5.3 `widgets/launch_promo_gate.dart` (baru)
`StatefulWidget` pembungkus `child` (pola sama `ReadOnlyWelcomeGate`, tapi
stateful). Bertanggung jawab atas **logika kapan tampil** (§6), bukan tampilan.
- **Dependensi:** `activeLaunchPopup()`, `memberStore`, `connectivityService`,
  `OnboardingScreen.hasSeen()`, flag launch-intent (§7), `rootNavigatorKey`,
  `AppAnalytics`, `LaunchPromoDialog`.
- **Antarmuka:** `const LaunchPromoGate({required Widget child})`.

### 5.4 `widgets/launch_promo_dialog.dart` (baru)
Konten visual popup "Hybrid" (§8) + fungsi `showLaunchPromoDialog(context, campaign)`.
Murni presentasi + callback; tidak tahu soal kondisi gate.
- **Dependensi:** `LaunchPopupCampaign`, token `NataloColors`, `AppProductImage`
  (untuk hero, reuse widget gambar yang sudah ada), `AppHaptics`.
- **Callback:** `onCta(href)` dan `onDismiss()` di-handle pemanggil (gate).

## 6. Logika tampil / skip (inti)

Dijalankan **sekali per proses** oleh `LaunchPromoGate`.

**Penanda proses (in-memory, TIDAK ke disk):**
`bool _shownThisProcess = false`. Karena frekuensi = "tiap cold start", tidak ada
flag persist di `SharedPreferences`. Proses baru (cold start) = kesempatan tampil baru.

**Urutan evaluasi:**
1. Ada campaign? `activeLaunchPopup()` != null. Kalau null → berhenti.
2. Tunggu `WidgetsBinding.addPostFrameCallback` (frame pertama selesai).
3. Tunggu `memberStore.initialized == true` (profil selesai dibaca dari disk;
   `isLoggedIn` bisa berubah false→true setelah load async). Kalau belum, pasang
   listener sekali dan lanjut saat sudah `initialized`.
4. Tunggu **settle delay** singkat (~900 ms, sedikit lebih lama dari delay 800 ms
   navigasi push) supaya flag launch-intent (§7) sempat resolve.
5. Cek kondisi skip — **semua** harus lolos:
   - `memberStore.isLoggedIn == true` (member-only)
   - `OnboardingScreen.hasSeen() == true` (bukan sesi onboarding)
   - `connectivityService.isOnline == true` (bukan offline)
   - `deepLinkService.launchedFromDeepLink == false` **dan**
     `pushNotificationService.launchedFromColdPush == false`
   - **Pengaman kedua:** route teratas pada `rootNavigatorKey` masih Home (`'/'`).
     Kalau deep-link/push sudah menavigasi ke layar lain (race timing), otomatis skip.
6. Kalau semua lolos & `_shownThisProcess == false` → set `_shownThisProcess = true`,
   catat `AppAnalytics` `popup_shown`, dan `showLaunchPromoDialog(...)`.

**Aksi tombol:**
- **CTA:** tutup dialog dulu (`Navigator.pop`), lalu
  `deepLinkService.handleExternalUri(campaign.ctaHref)` (reuse jalur `/produk/<slug>`
  yang sudah ada → fetch produk → buka `/product-detail`; fallback ke pencarian
  bila slug tak ketemu). Catat `popup_cta_click`.
- **Dismiss** (X / tombol dismiss / tap area gelap / back Android): tutup dialog.
  Catat `popup_dismiss`. Tidak ada persist — muncul lagi di cold start berikutnya.

## 7. Perubahan pada kode yang sudah ada

Minimal dan terlokalisasi:

### 7.1 `services/deep_link_service.dart`
Tambah flag publik launch-intent:
```dart
bool launchedFromDeepLink = false;
```
Set `true` di `initialize()` ketika `final initial = await _appLinks.getInitialLink()`
menghasilkan non-null (app dibuka via tap link saat cold start).

### 7.2 `services/push_notification_service.dart`
Tambah flag publik:
```dart
bool launchedFromColdPush = false;
```
Set `true` di `initialize()` ketika `messaging.getInitialMessage()` menghasilkan
non-null (app dibuka via tap notifikasi saat terminated).

### 7.3 `main.dart`
Sisipkan `LaunchPromoGate` di rantai builder, membungkus subtree Home:
```dart
child: ReadOnlyWelcomeGate(
  child: LaunchPromoGate(          // BARU
    child: ColoredBox(...),
  ),
),
```
Tidak ada perubahan pada urutan init `main()` yang lain.

## 8. Spesifikasi tampilan popup ("Hybrid")

Mengikuti mockup varian C yang disetujui.

- **Barrier/scrim:** `showGeneralDialog` dengan `barrierColor` gelap
  (`rgba(15,23,42,.55)`), `barrierDismissible: true`, animasi fade + skala halus
  (hormati `MotionPrefs.shouldReduce`).
- **Kartu:** `surface` putih, sudut `20`, lebar ~86% layar, maksimal ~400 lebar,
  `mainAxisSize.min`, aman terhadap notch (SafeArea).
- **Hero (opsional):** kalau `imageUrl != null`, tampilkan `AppProductImage`
  rasio ~16:9 dengan sudut atas membulat. Kalau null → langsung ke konten teks.
  Chip kategori (§tone) overlay kiri-atas pada gambar, atau di atas judul bila
  tanpa gambar.
- **Nada (tone):** reuse pola `_AnnouncementTone` dari `announcement_detail_screen.dart`:
  - `promo` → merah `#E11D48`, soft bg `#FFEEF2`
  - `announcement` → hijau `#20B26B`, soft bg `#E8F8F0`
- **Judul:** `textPrimary`, ~18–20px, `w500–w900` sesuai skala app.
- **Body:** `textSecondary`, ~13–14px, maksimal ~3 baris (ellipsis).
- **Tombol** (pill, `borderRadius 999`):
  - Utama: latar `NataloColors.primary` (#1E5FBF), teks putih, label `ctaLabel`.
  - Sekunder (dismiss): latar `primarySoft` (#EEF4FF)/teks primary, label `dismissLabel`.
  - Bila `ctaLabel == null` (mode pengumuman murni) → satu tombol dismiss lebar penuh.
- **Tombol X:** lingkaran kecil kanan-atas kartu.
- **Tipografi/warna:** semua dari `NataloColors` / `NataloTextStyles` — tanpa
  warna hardcode baru.

## 9. Analytics

Pakai `AppAnalytics` yang sudah ada (sesuaikan dengan signature method di
`services/app_analytics.dart`). Tiga event, semua membawa `campaignId`:
- `launch_popup_shown`
- `launch_popup_cta_click`
- `launch_popup_dismiss`

## 10. Testing

Widget test untuk `LaunchPromoGate` (logika kondisi):
- Tampil saat: login + onboarding-seen + online + bukan deep-link/push + ada campaign.
- Skip saat masing-masing kondisi dilanggar (5 kasus).
- Tampil **sekali** walau widget rebuild (cek `_shownThisProcess`).

Catatan penting (dari pengalaman repo ini): **jangan pakai `pumpAndSettle`** kalau
dialog merender gambar via `AppProductImage` — shimmer-nya tidak pernah "settle"
dan test menggantung. Gunakan **bounded pump-loop**, mock `SharedPreferences`,
dan inject/mock `memberStore` + service (flag launch-intent, connectivity) agar
kondisi terkontrol. Untuk kasus dasar, uji dulu campaign **tanpa gambar**
(`imageUrl: null`) supaya bebas dari shimmer.

## 11. Jalur upgrade ke admin-managed (masa depan)

Berkat sekat bersih, upgrade hanya menyentuh **satu tempat**:
- Ganti `activeLaunchPopup()` agar membaca hasil fetch API (mis. endpoint baru
  `/api/app-popup` atau reuse `/api/notifications/me` yang difilter flag
  `showAsPopup`). Model `LaunchPopupCampaign` sudah cocok dengan bentuk data
  promo/announcement + `href` (pola sama `HomeBanner.href`).
- UI, gate, analytics, dan logika skip **tidak berubah**.
- Saat itu baru pertimbangkan: frequency cap / "jangan tampilkan lagi",
  penjadwalan mulai–selesai, dan admin UI di website.

## 12. Risiko & catatan

- **"Tiap cold start" bisa terasa agresif.** Karena member-only + tanpa opsi
  bungkam, member setia melihatnya tiap buka app. Diterima untuk v1 (satu campaign,
  mudah dimatikan via `_campaign = null`). Mitigasi (frequency cap / opt-out)
  ditunda ke fase admin-managed.
- **Race timing launch-intent.** Flag deep-link/push di-set async saat
  `initialize()`. Settle delay (~900 ms) + pengaman "route teratas masih Home"
  menutup celah ini. Perlu diverifikasi di device saat implementasi.
- **CTA produk butuh jaringan.** `handleExternalUri('/produk/<slug>')` fetch by
  slug; bila gagal, fallback ke pencarian (perilaku existing) — bukan crash.
- **`slug` produk unggulan** untuk `ctaHref` harus diisi nilai nyata sebelum rilis.
```
