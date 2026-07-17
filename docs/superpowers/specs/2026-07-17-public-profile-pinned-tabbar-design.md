# Profil publik: tab bar pinned diam + kaca muncul dari belakang — Design

## Latar belakang

Tab bar konten profil publik (Postingan/Video/Belanja) saat ini punya bug transisi nyata: ikonnya **bergeser posisi** secara terpisah dari kemunculan alas kacanya, sehingga ada jendela waktu di mana ikon (dan pada tab aktif, kadang teks) melayang **tanpa alas apa pun di atas grid** — terlihat seperti "ikon hitam berkedip"/UI bug saat scroll.

### Akar penyebab (dikonfirmasi dari kode)

- `PublicProfileHeaderMotion.resolve` ([public_profile_header_motion.dart:39-41](../../../flutter_app/lib/widgets/public_profile_header_motion.dart)) menghitung dua variabel independen dari `progress` yang sama tapi jendela beda:
  - `tabTravel = _interval(progress, 0.20, 0.78)` — mulai gerak di **0.20**.
  - `pillOpacity = _interval(progress, 0.38, 0.78)` — alas baru mulai muncul di **0.38**.
- `PublicProfileChromeOverlay.build` ([public_profile_chrome_overlay.dart:116-120](../../../flutter_app/lib/widgets/public_profile_chrome_overlay.dart)) memakai `tabTravel` untuk me-lerp posisi tab bar (`tabTop`) dari `expandedTop` (di bawah identity) ke `collapsedTop` (nempel toolbar), dan `horizontalInset` dari 0→16.
- Karena `tabTravel` (gerak) mendahului `pillOpacity` (alas), ada jendela `progress ≈ 0.20–0.38` di mana tab sudah bergerak lepas dari header tapi belum punya alas sama sekali → ikon telanjang di atas grid.
- Header profil publik BUKAN sliver collapsing sungguhan — dia satu `SliverToBoxAdapter` bertinggi tetap (`topPadding + toolbarHeight + identityHeight + tabHeight`, lihat `public_profile_screen.dart:834-871`) yang sekadar reserve ruang kosong; posisi visual tab bar digambar terpisah lewat `Positioned` yang di-lerp manual dari `scrollOffset` mentah. Toolbar (tombol back + chip identitas ringkas saat official) SUDAH pinned diam di `metrics.topPadding` sejak awal — cuma tab bar yang punya masalah geser ini.

### Keputusan desain (hasil diskusi dengan user)

Setelah membandingkan dengan Instagram dan mengeksplorasi beberapa alternatif visual (segmented solid bar, chip brand biru, dock mengambang, mini-profile bar, dll — lihat riwayat percakapan), user memilih: **pertahankan tampilan pill ikon+label yang sudah ada**, tidak redesain visual, cukup **perbaiki perilakunya**:

1. Posisi tab bar **diam total** sejak frame pertama — tidak pernah berpindah koordinat sepanjang scroll.
2. Identity (avatar/bio/tombol Mengikuti-Pesan) di atasnya **menyusut sungguhan** (bukan sekadar ter-scroll lewat) mengikuti mesin `CollapsingHeaderDelegate` yang sudah dipakai Beranda/Produk (PINNED-ONLY, 1:1 jari, lihat `collapsing_header_delegate.dart`).
3. Alas kaca pill (dan fade icon/teks) mengikuti **variabel progress yang sama persis** dengan penyusutan identity — sehingga kesannya kaca "keluar dari belakang" konten yang menghilang, bukan animasi terpisah yang bisa telat.
4. Perilaku fade teks→ikon-saja yang SUDAH ADA sekarang (label memudar duluan sebelum jadi ikon-only saat pinned penuh) **dipertahankan tanpa perubahan** — cuma waktunya yang diselaraskan ke `t` yang baru.

## Arsitektur

### Sebelum
```
NestedScrollView
  headerSliverBuilder: [ SliverToBoxAdapter(spacer tinggi tetap = toolbar+identity+tab) ]
  body: TabBarView(...)
Stack:
  - grid (di bawah)
  - PublicProfileChromeOverlay (Positioned.fill, AnimatedBuilder(scrollController))
      - toolbar row: Positioned(top: metrics.topPadding) — SUDAH pinned diam
      - tab bar: Positioned(top: lerp(expandedTop, collapsedTop, tabTravel)) — BERGERAK, ini sumber bug
```

### Sesudah
```
NestedScrollView
  headerSliverBuilder: [
    Positioned(top: metrics.topPadding) toolbar row tetap seperti sekarang (tidak diubah)
    SliverPersistentHeader(
      pinned: true,
      delegate: CollapsingHeaderDelegate(
        minHeight: metrics.tabHeight,          // hanya tab bar tersisa saat pinned
        maxHeight: metrics.identityHeight + metrics.tabHeight,
        builder: (context, t) => _PublicProfileIdentityAndTab(t: t, ...),
      ),
    )
  ]
  body: TabBarView(...)
_PublicProfileIdentityAndTab(t):
  Column(
    children: [
      SizedBox(height: lerp(identityHeight, 0, t), child: identity content, opacity: 1 - t*1.4 clamp),
      SizedBox(height: tabHeight, child: PublicProfileContentTabBar(... pakai t sebagai progress alas/fade)),
    ],
  )
```

Tab bar tidak lagi punya `Positioned(top: lerp(...))` sendiri — dia bagian tetap dari `Column` yang otomatis "naik" ke posisi finalnya begitu identity di atasnya menyusut habis (konsekuensi natural sliver pinned), BUKAN animasi posisi terpisah yang kita hitung manual.

**Toolbar row (back button + chip identitas ringkas official) TIDAK diubah** — tetap `Positioned` pinned di atas segalanya seperti sekarang persis, karena itu memang sudah benar.

## Komponen yang berubah

### `PublicProfileHeaderMotion` (`public_profile_header_motion.dart`)
- **Hapus** field `tabTravel` — tidak ada lagi kebutuhan variabel geser posisi.
- Field kosmetik yang tersisa (`labelOpacity`, `pillOpacity`, `underlineOpacity`, `glassOpacity`, `compactIdentityOpacity`, `controlSurfaceOpacity`, `blurSigma`) tetap ada, tapi:
  - `pillOpacity = _interval(t, 0.0, 0.55)` — mulai di **progress 0** (bukan 0.38), selesai di 0.55 (dipercepat dari 0.78 karena `t` kini linear 1:1, bukan smoothstep — rentang lama dikalibrasi untuk kurva yang sudah dihapus).
  - `labelOpacity = _interval(t, 0.0, 0.45)` — tetap memudar SELESAI lebih dulu dari `pillOpacity` (urutan lama dipertahankan: teks hilang duluan, baru alas menguat penuh), tapi kini SAMA-SAMA mulai di 0 (bukan `pillOpacity` menyusul telat di 0.38 seperti sebelumnya) — inilah inti perbaikannya.
  - `underlineOpacity = 1 - _interval(t, 0.0, 0.30)` (garis bawah versi expanded memudar duluan, sebelum `labelOpacity` selesai) dan `glassOpacity`/`controlSurfaceOpacity` tetap `_interval(t, 0.50, 0.88)` seperti sekarang — tidak menyentuh posisi, jadi tidak ada bug untuk diperbaiki di variabel-variabel ini.
  - Nilai `progress` yang di-resolve fungsi ini sekarang berasal dari `t` milik `CollapsingHeaderDelegate` (linear 1:1 jari), BUKAN dari `scrollOffset` mentah + kurva easing manual (`raw * raw * (3 - 2*raw)`) — smoothstep dibuang karena sliver pinned sudah linear-1:1 secara native (match komentar `collapsing_header_delegate.dart`: "SYARAT WAJIB: tinggi konten linear terhadap t").
  - Reduced-motion tidak butuh percabangan progress lagi (sudah otomatis linear) — hanya `blurSigma` yang tetap 0 saat reduced motion.

### `PublicProfileChromeOverlay` (`public_profile_chrome_overlay.dart`)
- **Hapus** logic `tabTop`, `horizontalInset`, `expandedTop`, `collapsedTop` yang di-lerp manual.
- Toolbar row (back button + chip identitas ringkas) **tidak berubah** — tetap `Positioned(top: metrics.topPadding, height: metrics.toolbarHeight)`, opacity-nya (`controlSurfaceOpacity`, `compactIdentityOpacity`) tetap dikemudikan `motion` yang sama, cuma sumber `t`-nya kini dari delegate bukan scroll mentah.
- Tab bar dan identity **dipindah keluar** dari `PublicProfileChromeOverlay` menjadi isi `CollapsingHeaderDelegate.builder` di `public_profile_screen.dart` (lihat di bawah) — `PublicProfileChromeOverlay` HANYA berisi toolbar row lagi (tanggung jawabnya menyempit).

### `public_profile_screen.dart`
- `_buildBody()`: ganti `SliverToBoxAdapter` (spacer identity+tab tetap) menjadi `SliverPersistentHeader(pinned: true, delegate: CollapsingHeaderDelegate(...))`.
- Builder baru `_PublicProfileIdentityAndTab` (widget kecil, private ke file ini atau file baru `public_profile_identity_tab_header.dart` — keputusan file-split di rencana implementasi) menerima `t` dari delegate, merender:
  - `PublicProfileExpandedHeader` (identity content yang SUDAH ADA, tidak diubah tampilannya) dibungkus supaya tingginya **benar-benar mengecil linear** dari `identityHeight` ke `0` mengikuti `t` (pakai `SizedBox(height: lerp)` + `ClipRect` supaya konten tidak reflow aneh, opacity clamp seperti mockup: `1 - t*1.4` di-clamp 0..1) — sesuai syarat wajib delegate (tinggi linear terhadap `t`).
  - `PublicProfileContentTabBar` (SUDAH ADA, tidak diubah tampilannya) di baris tetap paling bawah `Column` ini, menerima `labelOpacity`/`pillOpacity`/`underlineOpacity` dari `PublicProfileHeaderMotion.resolve(progress: t, ...)`.
- `metrics.scrollSpaceHeight`/`collapsedChromeHeight` tetap dipakai tapi kini sebagai `maxHeight`/`minHeight` delegate, bukan `collapseDistance` untuk kurva scroll mentah.
- `_scrollController` tetap ada untuk keperluan lain (mis. refresh indicator, `NataloPawRefreshIndicator`) — TIDAK dipakai lagi untuk resolve motion tab bar (`AnimatedBuilder(animation: _scrollController)` di overlay lama dihapus karena `t` datang dari delegate build, bukan listener manual).

## Yang TIDAK berubah

- Tampilan pill (ikon+label, warna aktif/inactive, radius, ukuran) — sama persis seperti `PublicProfileContentTabBar` sekarang.
- Perilaku fade "teks hilang jadi ikon-saja saat scroll" — dipertahankan, cuma waktunya diselaraskan.
- Toolbar row (back + chip identitas ringkas official) — posisi & perilaku pinned-nya sudah benar sekarang, tidak disentuh.
- `PublicProfileExpandedHeader` (avatar/nama/bio/tombol) — tidak ada perubahan konten/tampilan, hanya dibungkus supaya tingginya bisa di-drive `t`.
- Halaman lain (Beranda, Produk) — tidak tersentuh; `CollapsingHeaderDelegate` dipakai ulang apa adanya, tanpa modifikasi ke file itu sendiri.
- Profil MILIK SENDIRI (tab "Akun") dan varian profil lain di luar `PublicProfileScreen` — di luar scope spec ini kecuali terbukti share komponen yang sama (perlu dicek saat implementasi; kalau ternyata terpisah, tidak disentuh).

## Testing

- `public_profile_header_motion_test.dart` — assert ulang: `tabTravel` sudah tidak ada (hapus test-nya), `pillOpacity` mulai di progress 0, tetap dokumentasikan interval baru.
- `public_profile_chrome_overlay_test.dart` — assert toolbar row tetap pinned diam; assert tab bar TIDAK LAGI jadi tanggung jawab widget ini (pindah expect ke test screen/header baru).
- Test baru untuk `_PublicProfileIdentityAndTab`/`CollapsingHeaderDelegate` integration: pump beberapa `shrinkOffset` sampel (mis. 0%, 25%, 55%, 100% dari `identityHeight`) dan assert `tester.getTopLeft()` pada `Key('public_tab_posts_pill')` (atau induknya) menghasilkan **koordinat Y layar yang identik** di semua sampel — ini bukti langsung "ikon diam total", pengganti asersi lama yang menyebut `tabTravel` (variabel itu sudah tidak ada).
- `public_profile_screen_test.dart` — sesuaikan setup scroll simulation dari raw `scrollController.jumpTo` ke assert lewat `shrinkOffset` sliver (masih bisa pakai scroll gesture yang sama, cuma assertion targetnya berubah).
- Golden `public_profile_premium_test.dart` — regenerasi golden yang kena dampak posisi tab bar (tampilan akhirnya seharusnya identik secara visual di titik expanded=0% dan pinned=100%, jadi golden existing di dua titik itu semestinya TIDAK berubah; kalau berubah berarti ada regresi tampilan yang perlu diinvestigasi, bukan di-terima begitu saja).

## Non-goals

- Tidak mengganti tampilan pill jadi segmented-solid/chip-brand/dock/mini-profile — semua alternatif itu didiskusikan tapi TIDAK dipilih.
- Tidak mengubah halaman profil lain (Beranda/Produk/Akun) di luar `PublicProfileScreen`.
- Tidak menambah fitur baru pada tab bar (badge, count, dsb).
