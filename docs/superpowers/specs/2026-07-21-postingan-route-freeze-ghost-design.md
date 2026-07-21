# Design — OriginExpansionRoute: animasi tak boleh beku (ghost viewer + profil nyangkut)

Tanggal: 2026-07-21
Status: Menunggu review user

## Masalah (terverifikasi di device iOS + Android, post foto maupun video)

Bukti: screenshot device + screen recording 26 dtk (frame dianalisis satu-satu). Tiga gejala:

1. **Ghost beku saat back:** setelah back dari viewer "Postingan", viewer tetap tampil semi-transparan (~40%) menumpuk di atas halaman profil — kadang permanen, kadang pulih setelah interaksi lain.
2. **Ghost saat viewer tampil "normal":** konten halaman di belakang (nama profil, avatar) tembus di area atas viewer; ghost baris author post pertama menumpuk di atas judul "Postingan" saat scroll ke post berikutnya.
3. **Profil "terdorong ke atas":** setelah back, blok identitas profil (avatar/statistik/bio/tombol) hilang — tab bar menempel di toolbar, konten tidak kembali ke tempatnya, dan halaman sering tidak merespons sentuhan.

## Akar masalah

Transisi profil→viewer memakai `_OriginExpansionPageRoute` (`lib/widgets/origin_expansion_route.dart`) — `PageRoute` custom **non-opaque** (`opaque: false`, `barrierColor: Colors.transparent`, baris 87-90) dengan morph snapshot + **gesture back-swipe tepi 28px buatan sendiri** (`_OriginEdgeBackGestureDetector` + `_OriginBackGestureController`, baris 173-355).

Fakta kunci yang menyatukan ketiga gejala: **opacity halaman tujuan adalah fungsi nilai animasi route** (`Interval(0.55, 1)`, baris 439-452), dan halaman tujuan SUDAH punya latar opaque (`ColoredBox`, baris 453-456). Artinya semua "ghost/tembus" hanya mungkin terjadi ketika **nilai animasi route berhenti di bawah 1.0** (buka) atau **di tengah jalan menuju 0** (tutup). Bug-nya bukan visual — bug-nya adalah **nilai animasi yang bisa dibekukan** oleh mesin gesture:

- **Celah 1 — pop saat drag aktif membekukan penutupan selamanya.** Saat jari men-drag tepi dan pop datang dari sumber lain (tombol back di AppBar viewer via `Navigator.maybePop`, back sistem Android), `didPop` memulai `controller.reverse()`; `dragUpdate` berikutnya (`controller.value -= delta`, baris 273-276) **menghentikan reverse itu dan mengunci nilainya**. Saat jari lepas, `dragEnd` melihat `!getIsCurrent()` → `abort()` → `_finish()` (baris 278-283, 296-298) yang hanya melepas listener — **tidak ada yang melanjutkan animasi**. Route sudah keluar dari histori tapi tidak pernah `dismissed` → overlay-nya tidak pernah difinalisasi → ghost permanen di nilai terakhir jari. (Gejala 1.)
- **Celah 2 — drag mentok 0 sebelum pop.** `dragUpdate` tanpa clamp bisa membuat nilai menyentuh 0.0 ketika route masih current. `dragEnd` lalu memanggil `navigator.pop()` → `reverse()` dari 0 **tidak menghasilkan perubahan status baru** (status sudah `dismissed` sejak sebelum pop) → listener disposal internal framework tidak terpicu → route mati-tak-terfinalisasi **tanpa terlihat** + `ModalBarrier` transparannya tetap menelan semua input di atas profil. (Kontributor utama gejala 3: profil tampak beku di state terakhir dan tidak merespons; "kadang pulih" saat navigasi berikutnya kebetulan mem-flush histori.)
- **Celah 3 — gesture menginterupsi animasi BUKA.** Sentuhan di tepi kiri selama animasi buka masih berjalan bisa memulai pop-gesture dan membekukan nilai < 1.0 → viewer "mapan" dengan opacity < 1 → konten halaman belakang tembus. (Gejala 2. Syarat mulai gesture harus mencakup `animation.isCompleted`.)

Gejala 3 juga punya kandidat penyebab kedua yang berdiri sendiri (di luar barrier): pergeseran offset outer `NestedScrollView` profil saat grid di-rebuild oleh `_loadAll()` sesudah kembali (`member_screen.dart:346,391-427` — tanpa `SliverOverlapAbsorber`). Kepastiannya ditentukan lewat test saat implementasi.

## Tujuan — invariant yang harus ditegakkan

- **I1:** Begitu route ter-pop (`didPop`), nilai animasi WAJIB mencapai `dismissed` (0.0) dalam waktu terbatas; tidak ada input gesture yang boleh menghentikannya.
- **I2:** Setiap jalur akhir gesture (`dragEnd`, `abort`, `dispose`, `onCancel`) meninggalkan route dalam salah satu dari dua keadaan sah: (a) masih current dengan nilai kembali ke 1.0 (spring back), atau (b) ter-pop dan sedang/berakhir menuju 0.0. Tidak pernah beku di tengah.
- **I3:** Gesture back hanya boleh dimulai saat animasi buka sudah selesai (`status == completed`).
- **I4:** Setelah back, profil kembali ke posisi scroll semula (blok identitas terlihat bila sebelumnya terlihat) dan merespons sentuhan.

## Non-tujuan

- TIDAK mengubah rasa/durasi/kurva morph (300ms buka / 250ms tutup, kurva emphasized — baris 15-16, 104-107 dipertahankan persis).
- TIDAK mengubah arsitektur route (tetap non-opaque + snapshot morph) atau ambang gesture (28px / 0.25 / 800 px-s).
- TIDAK menyentuh desain appbar transparan viewer — bila setelah fix masih ada tembus-konten di bawah toolbar saat kondisi mapan, itu keputusan desain terpisah (follow-up).
- TIDAK menyentuh isu glitch dekode video Xiaomi (investigasi terpisah yang masih berjalan).
- TIDAK memakai watchdog timer (gotcha lama: watchdog menutupi kegagalan test — `comment-drawer-terminal-state`).

## Pendekatan

Semua perubahan inti di `lib/widgets/origin_expansion_route.dart`:

### 1. `_OriginBackGestureController.dragUpdate` — tutup Celah 1 + 2

```dart
void dragUpdate(double delta) {
  if (!_active) return;
  // Route sudah ter-pop dari sumber lain saat jari masih di layar —
  // reverse() yang sedang berjalan TIDAK boleh dihentikan oleh drag.
  if (!getIsCurrent()) return;
  // Clamp bawah ke epsilon: nilai tidak boleh menyentuh 0.0 selagi route
  // masih current — status `dismissed` prematur membuat pop berikutnya
  // tidak menghasilkan notifikasi status → route tak pernah difinalisasi.
  controller.value = (controller.value - delta).clamp(0.001, 1.0);
}
```

### 2. `_OriginBackGestureController.abort` — tutup Celah 1 (jalur lepas jari)

```dart
void abort() {
  // Route sudah ter-pop tapi animasi penutup sempat dihentikan/belum
  // selesai → lanjutkan sampai tuntas supaya route difinalisasi dan
  // barrier-nya dilepas. Tanpa ini: ghost beku / layar menelan input.
  if (!getIsCurrent() &&
      controller.status != AnimationStatus.dismissed &&
      !controller.isAnimating) {
    controller.animateBack(0, curve: _kOriginCloseCurve);
  }
  _finish();
}
```

Catatan urutan: `_finish()` tetap dipanggil segera (melepas `didStopUserGesture` supaya Navigator bisa mem-flush histori); finalisasi route terjadi otomatis oleh listener internal `TransitionRoute` begitu `dismissed` tercapai. `animateBack` memakai durasi default controller (`reverseTransitionDuration` 250ms) — cukup, tidak perlu durasi proporsional.

### 3. Syarat mulai gesture — tutup Celah 3

Di `buildTransitions` (baris 130-131), `enabledCallback` diperketat:

```dart
enabledCallback: () =>
    popGestureEnabled && controller!.status == AnimationStatus.completed,
```

Sentuhan tepi selama animasi buka berjalan tidak lagi bisa memulai pop-gesture (perilaku sama dengan `CupertinoRouteTransitionMixin` standar).

### 4. `dragEnd` jalur `shouldPop` — pertahankan + kini aman

Dengan clamp epsilon dari #1, nilai tidak pernah 0.0 saat `navigator.pop()` dipanggil → `reverse()` dari ε selalu menghasilkan transisi status → `dismissed` terpicu normal → framework memfinalisasi route. Guard existing baris 290 (`if (controller.status == dismissed) _finish()`) dipertahankan sebagai lapis kedua.

### 5. Bug profil (I4) — verifikasi-lewat-test, fix kondisional

Hipotesis utama: gejala profil adalah efek hilir Celah 2 (barrier route-mati menelan input + halaman tampak beku) — fix #1-#4 menyembuhkannya. Implementasi WAJIB membuktikan lewat widget test reproduksi (buka viewer dari `_ProfilePage` → pop → assert blok identitas terlihat + profil merespons tap). Bila test menunjukkan masih ada pergeseran offset outer `NestedScrollView` setelah `_loadAll()` rebuild (kandidat kedua), fix lanjutan berada di `member_screen.dart`: pertahankan offset outer saat rebuild grid (bukan mengubah struktur NestedScrollView). Keputusan itu diambil berdasarkan bukti test, bukan asumsi.

## Testing

Widget test baru `test/widgets/origin_expansion_route_dismiss_test.dart` (memakai hook existing `debugOriginExpansionStatusObserver` + Navigator asli + `WidgetController.startGesture` untuk drag tepi):

1. **Pop programatik saat drag aktif** (Celah 1): mulai drag tepi → `Navigator.pop()` dari kode → lanjutkan drag beberapa frame → lepas → assert status mencapai `dismissed`, route hilang dari tree, dan halaman di bawah menerima tap.
2. **Drag mentok kiri lalu lepas** (Celah 2): drag sampai delta > lebar layar → lepas → assert `dismissed` + route ter-finalisasi + tap pada halaman bawah berfungsi (barrier tidak menyisa).
3. **Drag tanggung lalu lepas** (regresi): < 25% & pelan → spring back ke 1.0, route tetap current, konten viewer penuh (opacity 1).
4. **Sentuh tepi saat animasi buka** (Celah 3): mulai buka → drag tepi di tengah animasi → assert nilai animasi tetap mencapai 1.0 (completed), tidak beku.
5. **Regresi test existing** `test/widgets/origin_expansion_route_test.dart` tetap hijau.

Test profil (I4) di `test/screens/member_screen_profile_restore_test.dart`: mount `_ProfilePage` (atau `MemberScreen` dengan seam yang ada) → buka viewer via grid → pop → assert identitas terlihat + `tester.tap` pada elemen profil berfungsi. (Bounded pump, tanpa `pumpAndSettle` — konvensi test project.)

## Verifikasi akhir

`flutter analyze` bersih + suite penuh (bandingkan dengan baseline 9 kegagalan pre-existing yang sudah terdokumentasi) + device-verify iOS & Android pada alur video rekaman user: profil→post→back berulang, back-button + swipe bersamaan, swipe tanggung, swipe cepat penuh.

## Ringkasan perubahan file

- **Modifikasi:** `lib/widgets/origin_expansion_route.dart` (dragUpdate guard+clamp, abort lanjutkan animasi, enabledCallback + status completed)
- **Baru:** `test/widgets/origin_expansion_route_dismiss_test.dart`, `test/screens/member_screen_profile_restore_test.dart`
- **Kondisional (hanya bila test membuktikan):** `lib/screens/member_screen.dart` (preserve offset outer saat rebuild)
- **Tidak berubah:** kurva/durasi morph, ambang gesture, arsitektur non-opaque route, semua layar pemakai route (`member_screen`, `public_profile_screen`, `member_posts_screen`, `post_gallery_opener`)
