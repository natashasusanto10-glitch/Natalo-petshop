# Design — Media picker "Post Baru": frame preview fixed ala IG (hilangkan resize + terpress)

Tanggal: 2026-07-21
Status: Menunggu review user

## Masalah (SS device vs IG, foto sama)

Layar "Post Baru" (`feed_media_picker_screen.dart`) preview foto berbeda dari IG dalam dua hal yang membuatnya terasa salah:

1. **Terpress/kecil:** frame preview hanya **75% lebar layar** (`screenWidth * 0.75`, baris 887) dengan foto default *contain* → foto tampil kecil dengan ruang gelap. IG: frame **full-width**, default *cover* → foto besar, natural.
2. **Layout melompat saat toggle:** ikon toggle kiri-bawah tidak hanya mengganti cara foto mengisi frame — ia **mengubah ukuran/rasio frame itu sendiri** (`_previewAspect` beralih dari 4:5 ke rasio natural foto, di-clamp 0.5–1.91; baris 178-186). Akibatnya seluruh layout bergeser dan grid galeri di bawah terdorong (dari ~3 baris jadi ~1 baris). IG: frame **tidak pernah berubah ukuran**; hanya cara foto mengisi frame yang berganti (cover ↔ contain), grid diam total.

Komentar kode baris 892 & 990 masih menyatakan "Frame tetap 4:5; yang berubah hanya fit" — itu desain LAMA; kode sejak itu diubah jadi resize-frame tanpa memperbarui komentar. Spec ini mengembalikan perilaku ke fixed-frame (yang memang niat awal) + full-width.

## Yang SUDAH benar (tidak disentuh)

- **Kontrak toggle → hasil post** (`photo_crop_export.dart:109-146`): `preserveOriginal=false` (cover) → foto di-crop ke frame `targetAspect` dengan pinch/pan per foto; `preserveOriginal=true` (contain) → rasio asli foto dipertahankan (tanpa crop). Ini identik dengan IG (crop vs "post utuh") dan BENAR.
- **Toggle global** untuk semua foto carousel (`_previewFitOriginal` satu untuk semua) — sama IG.
- **Transform crop per-foto** (`_photoCropTransforms`) + strip re-crop di bawah preview (`_buildThumbStripSection`) — tetap.
- **Widget `_PhotoCropPreview`** sudah mendukung `fitOriginal` → `BoxFit.contain` (letterbox) vs cover (`photo_crop_preview.dart:447-461`) — di dalam frame 4:5 fixed, contain menghasilkan letterbox persis IG. Tidak diubah.
- Pra-muat dimensi gambar (`_loadPreviewImageSize` / `_previewImageSize`) sebagai optimasi anti-flash ke `_PhotoCropPreview` — DIPERTAHANKAN (lihat Non-tujuan).

## Keputusan (dikonfirmasi user)

Frame preview **fixed, full-width, rasio 4:5** (bukan 1:1 IG). Alasan: default crop feed kita 4:5 dan feed me-render 4:5 — frame 4:5 membuat preview **jujur** terhadap hasil post. Meniru 1:1 IG mentah akan membuat preview berbohong (atau memaksa mengubah kebijakan crop feed — di luar scope). Satu-satunya beda visual dari IG hanyalah rasio bingkai; semua perilaku lain (cover default, letterbox saat toggle, grid diam) sama IG.

## Tujuan

1. Frame preview **selebar layar** (full-width, edge-to-edge seperti IG), **tinggi tetap** dari rasio 4:5 — TIDAK pernah berubah apa pun status toggle-nya.
2. Default **cover** (foto mengisi penuh + crop) — kesan pertama "natural".
3. Toggle → **contain** (foto utuh + letterbox) **di dalam frame 4:5 yang sama** — foto mengecil di dalam bingkai, bingkai tidak bergerak.
4. Grid galeri di bawah **tidak bergeser satu piksel pun** saat toggle.

## Non-tujuan

- TIDAK mengubah kontrak `preserveOriginal`/`fitOriginal` → hasil export (crop vs asli) — hanya geometri preview.
- TIDAK mengubah `_PhotoCropPreview`, `photo_crop_export.dart`, `photo_crop_transform.dart`.
- TIDAK mengubah rasio jadi 1:1 dan TIDAK mengubah default crop/render feed.
- TIDAK menghapus `_loadPreviewImageSize`/`_previewImageSize` — masih dipakai sebagai pra-muat anti-flash ke `_PhotoCropPreview` (baris 1104-1120); hanya berhenti dipakai untuk menghitung rasio frame.
- TIDAK menyentuh jalur video preview (`_previewType == video`) selain konsekuensi frame full-width yang sama (video tetap di frame yang sama; perilaku fit video tidak diubah).
- TIDAK mengubah posisi/bentuk ikon toggle, pill counter, atau strip re-crop.

## Pendekatan

Semua di `lib/screens/feed_media_picker_screen.dart`.

### 1. Frame rasio konstan

`_previewAspect` getter (baris 178-186) disederhanakan jadi konstanta:

```dart
double get _previewAspect => _defaultPreviewAspect; // 4:5 fixed, ala IG
```

Konsekuensi: saat `_previewFitOriginal=true`, frame TETAP 4:5 dan `_PhotoCropPreview(fitOriginal: true)` menampilkan foto `BoxFit.contain` → letterbox di dalam 4:5. Saat export, `preserveOriginal=true` tetap menghasilkan foto rasio-asli (kontrak lama utuh — `targetAspect` diabaikan di cabang `preserveOriginal`, jadi nilai 4:5 yang kini selalu dikirim tidak berpengaruh; lihat `photo_crop_export.dart:109-110`).

Hapus yang jadi mati akibat ini: konstanta `_minNaturalAspect`, `_maxNaturalAspect`. Perbarui komentar blok baris 153-162 supaya akurat (frame fixed 4:5; toggle = cover↔contain, BUKAN resize).

### 2. Frame full-width

Di `_buildPreview` (baris 883-931):

```dart
Widget _buildPreview() {
  return AspectRatio(
    aspectRatio: _previewAspect, // 4:5 fixed, full-width
    child: ClipRRect(
      borderRadius: BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [ /* _buildPreviewContent + toggle + counter, sama */ ],
      ),
    ),
  );
}
```

Menggantikan `LayoutBuilder` + `Center(child: SizedBox(width: screenWidth*0.75, child: AspectRatio(...)))`. Lebar mengikuti lebar parent (full width); tinggi = lebar × 5/4. `_previewImageSizeAssetId == asset.id ? _previewImageSize : null` di pemanggilan `_PhotoCropPreview` (baris 1120) TETAP.

### 3. Perbarui komentar stale

Baris 87 header ("Preview centered 75% lebar layar × ratio 3:4" — dobel salah: bukan 75%, bukan 3:4), baris 777, 892, 990: samakan dengan perilaku baru (full-width, 4:5 fixed, cover default / contain saat toggle).

## Testing

Widget test baru `test/screens/feed_media_picker_frame_test.dart` (mock `photo_manager` permission/asset via seam yang ada di test picker existing — pelajari `test/screens/feed_media_picker_transition_test.dart` untuk pola mount + mock; kalau mount penuh terlalu berat, uji unit murni geometri):

1. **Rasio frame konstan lintas toggle:** render preview → ukur tinggi frame (`tester.getSize` pada `AspectRatio`/preview key) → toggle `fitOriginal` → ukur lagi → **tinggi identik**. (Regresi utama: dulu berubah.)
2. **Full-width:** lebar frame == lebar layar (bukan 0.75×).
3. **Grid tidak bergeser:** posisi `top` elemen grid pertama sebelum & sesudah toggle == sama.
4. **`_previewAspect` selalu 4:5** untuk foto portrait maupun landscape (kalau digunakan seam yang meng-inject `_previewImageSize`).

Kalau harness mount penuh picker tidak praktis (butuh `photo_manager` platform), turunkan ke: ekstrak `_previewAspect` sudah konstan (uji lewat pemanggilan langsung bila di-expose `@visibleForTesting`), + widget test frame memakai `_PhotoCropPreview` terisolasi dengan `fitOriginal` true/false pada frame `AspectRatio(4/5)` → assert ukuran frame sama, child fit berubah. Implementer memilih level yang paling andal dan mendokumentasikannya.

## Verifikasi akhir

`flutter analyze` bersih + suite penuh (baseline: golden `member_screen_akun` pre-existing fail; kegagalan lain = regresi) + device-verify: foto portrait & landscape, toggle bolak-balik (frame diam, grid diam), hasil post cover vs utuh benar, carousel multi-foto.

## Ringkasan perubahan file

- **Modifikasi:** `lib/screens/feed_media_picker_screen.dart` (`_previewAspect` konstan, `_buildPreview` full-width, hapus 2 konstanta natural-aspect mati, perbarui 4 komentar stale)
- **Baru:** `test/screens/feed_media_picker_frame_test.dart`
- **Tidak berubah:** `photo_crop_export.dart`, `photo_crop_preview.dart`, `photo_crop_transform.dart`, kontrak toggle→hasil, `_loadPreviewImageSize`, jalur video, ikon/pill/strip
