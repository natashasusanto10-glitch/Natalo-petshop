# Design — Perlambat morph origin-expansion ke pace IG (Approach A)

Tanggal: 2026-07-18
Status: Disetujui (Approach A)

## Masalah

Morph "origin-expansion" (tap thumbnail grid → buka Postingan; juga tombol + → composer) terasa **lebih cepat** dari Instagram. Nilai sekarang di `_OriginExpansionPageRoute`:
- Buka: **240ms**, curve `Curves.easeOutCubic`
- Tutup: **220ms**, curve `Curves.easeInCubic`

240ms tergolong snappy/cepat; IG/iOS shared-element expand terasa lebih kalem & "mendarat" (~300ms) dengan curve emphasized (Material 3), bukan cubic murni. Nilai 240/220 sebelumnya ditetapkan sengaja di spec lama; sekarang di-override atas permintaan user untuk menyamai IG.

## Tujuan

Perlambat & haluskan morph origin-expansion agar pace-nya menyerupai IG, TANPA mengubah mekanik lain (reveal via clip-window, gesture edge-back, snapshot fade).

## Non-tujuan

- Tidak menyentuh morph video→fullscreen (`scaled_video_feed_route.dart`) — surface terpisah.
- Tidak mengubah reveal konten via clip-window saat buka (sudah IG-like: konten muncul mengikuti kotak membesar, opacity 1 di jalur snapshot).
- Tidak mengubah gesture edge-back + `SpringSimulation` spring-back (jalur `linearTransition`, tetap responsif 1:1).
- Tidak mengubah `Interval(0.55, 1)` fade konten fallback (jalur no-snapshot / reverse).

## Perubahan (Approach A)

Scope: **semua** pemakai `pushOriginExpansion` (satu route class), yaitu 4 alur — Akun grid→Postingan, "Postingan Saya" grid→Postingan, profil publik grid→Postingan, dan tombol +→media picker. Konsisten (satu perubahan), sejalan prinsip "semua transisi serasa sama".

File: `flutter_app/lib/widgets/origin_expansion_route.dart`.

1. **Durasi** (`_OriginExpansionPageRoute`):
   - `transitionDuration`: `240` → **`300`** ms
   - `reverseTransitionDuration`: `220` → **`250`** ms

2. **Curve** (`_OriginExpansionTransitionState.build`, baris ~427-430). Tambah dua konstanta bernama di file & pakai:
   - Buka (forward): `Curves.easeOutCubic` → **emphasized-decelerate** `Cubic(0.05, 0.7, 0.1, 1.0)`
   - Tutup (reverse): `Curves.easeInCubic` → **emphasized-accelerate** `Cubic(0.3, 0.0, 0.8, 0.15)`

   Baris saat ini:
   ```dart
   final progress = linear
       ? animationValue
       : (reverse ? Curves.easeInCubic : Curves.easeOutCubic)
           .transform(animationValue);
   ```
   Jalur `linear` (saat gesture edge-back berlangsung) TETAP linear — tidak disentuh.

## Testing

`flutter_app/test/widgets/origin_expansion_route_test.dart` memompa durasi lama untuk melewati transisi maju sampai selesai; harus diselaraskan ke durasi baru (test-timing, BUKAN pelemahan assertion):
- Baris 117: `pump(240ms)` → `pump(300ms)`
- Baris 502: `pump(241ms)` → `pump(301ms)`
- Baris 526: `pump(240ms)` → `pump(300ms)`
- Baris 121 (`pump(110ms)` saat reverse) dst.: reverse kini 250ms; sesuaikan bila assertion mid-reverse gagal, jaga intent-nya. Jalankan suite untuk konfirmasi mana yang perlu diubah.

Verifikasi: `flutter analyze` bersih + `flutter test test/widgets/origin_expansion_route_test.dart` hijau. Karena ini "feel", WAJIB device-verify visual (rasa pace) di iOS/Android; nilai gampang di-tweak bila meleset.

## Ringkasan file

- Modifikasi: `flutter_app/lib/widgets/origin_expansion_route.dart` (durasi + 2 konstanta curve).
- Modifikasi: `flutter_app/test/widgets/origin_expansion_route_test.dart` (selaraskan pump durasi).
