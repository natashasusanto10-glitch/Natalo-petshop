# Feed morph polish — anti-melar + satu kurva + simetri (spec #2–#4 + #6)

Tanggal: 2026-07-17
Status: disetujui (menunggu review spec)

Batch kedua dari audit transisi feed vs Instagram. #1 (reverse-target Detail
Produk) sudah MERGED (PR #153). #5 dibatalkan (Android instan sengaja, meniru
Shopee/Tokopedia — terdokumentasi di `main.dart:461-466`). #7 ditunda (redesign
header profil, bukan poles transisi).

## Masalah & keputusan

Morph video (`scaled_video_feed_route.dart`) terasa kurang halus dibanding IG
karena tiga hal, plus satu asimetri kecil di sheet komentar:

- **#2 melar** — thumbnail di-scale dengan me-lerp width & height **bebas**
  lalu `BoxFit.cover` pada rect yang aspeknya berubah → media meregang/gepeng.
- **#3 reframe** — entry morph pakai `cover`, sedangkan fullscreen steady-state
  pakai `fitWidth`+topCenter → framing "melompat" di akhir morph.
- **#4 opacity lepas sumber** — crossfade snapshot↔video membuat objek
  `CurvedAnimation` baru tiap build, bukan menurunkan nilai dari `t` yang sudah
  dihitung untuk rect.
- **#6 asimetri** — `FeedCommentMediaFrame` buka `easeOutCubic`, tutup
  `easeInOutCubic` (kurva berbeda dua arah).

Keputusan (disetujui lewat demo visual, "mekanik B"): pakai **clip-window** ala
IG. Feed utama tetap `cover` (tak disentuh).

## #2 + #3 — Clip-window pada `scaled_video_feed_route.dart`

Ganti mekanik: alih-alih memposisikan thumbnail pada rect yang di-lerp lalu
`cover`, render thumbnail **berukuran tetap sebesar layar tujuan** dengan fit
identik fullscreen, lalu animasikan hanya jendela cliprnya.

Struktur transition (menggantikan `Positioned` + `CachedNetworkImage` cover di
`buildTransition`, sekitar baris 92-137):

```
Positioned(  // jendela yang membesar origin → fullscreen (pakai t)
  left/top/width/height = lerp(activeOrigin, fullscreen, t),
  child: ClipRect(
    child: OverflowBox(
      alignment: Alignment.topCenter,
      minWidth/maxWidth: screenSize.width,
      minHeight/maxHeight: screenSize.height,   // isi selalu SEUKURAN LAYAR
      child: CachedNetworkImage(
        imageUrl: activeImageUrl,
        fit: BoxFit.fitWidth,                    // = _foregroundFit fullscreen
        alignment: Alignment.topCenter,          // = _foregroundAlign
      ),
    ),
  ),
)
```

- Konstanta fit/align disamakan dengan `feed_video_post_view.dart`:
  `BoxFit.fitWidth` + `Alignment.topCenter` (immersive). Media **tak pernah**
  berubah bentuk selama morph (aspek isi konstan) → hilang melar (#2).
- Karena framing morph = framing fullscreen, tak ada lompatan `cover→fitWidth`
  di titik crossfade (#3, jalur morph).
- `borderRadius`: `activeBorderRadius * (1 - t)` dari `t` yang sama (tetap).
- Latar hitam untuk area kosong bawah tetap ada (`errorWidget`/ColoredBox),
  konsisten dengan `_mediaStack`.

Catatan diskontinuitas: sumber thumbnail (kartu Detail Produk / feed) tampil
`cover`, sedang morph mulai dari `fitWidth` slice — pada frame t≈0 window sangat
kecil (≈ ukuran thumbnail) sehingga selisih crop nyaris tak terlihat, lalu cepat
menuju framing fullscreen yang benar. Dapat-diterima; tidak menganimasikan fit
itu sendiri (over-engineering, di luar scope).

`mainFeed` framing (`FeedVideoFraming.mainFeed`, `BoxFit.cover`) **tidak
diubah**.

## #4 — Satu sumber progress untuk opacity

Di `scaled_video_feed_route.dart`, snapshot & destinasi saat ini masing-masing
membangun `CurvedAnimation(parent: animation, curve: Interval(0.55,1.0,...))`
baru di dalam `builder`. Ganti agar opacity diturunkan dari `t` yang sudah
dihitung (`curved.value`), lewat `Interval(0.55, 1.0, curve: Curves.easeIn)
.transform(t)` — nilai numerik sama persis, tapi satu sumber kebenaran, tanpa
objek Animation duplikat per-build.

Klarifikasi (koreksi audit): rect & radius **sudah** memakai `t` yang sama; yang
perlu dirapikan hanya sumber opacity. `origin_expansion_route.dart` sudah
menurunkan opacity dari `progress`/interval `animationValue` secara konsisten dan
**tidak** diubah di batch ini.

## #6 — Simetri buka/tutup `FeedCommentMediaFrame`

`feed_comment_sheet.dart:375` — ganti kurva pada arah tutup:

```
curve: open ? Curves.easeOutCubic : Curves.easeInOutCubic,
// → menjadi:
curve: Curves.easeOutCubic,   // sama untuk buka & tutup
```

Durasi `open ? 260 : 220` dibiarkan (perbedaan durasi wajar; yang mengganggu
adalah kurva berbeda). Caption `AnimatedSize` (`feed_creator_overlay.dart:494`)
sudah satu-kurva (easeOutCubic dua arah, beda durasi saja) → tidak diubah.

## Non-tujuan

- Feed utama `cover` → `fitWidth` (lintas-permukaan di luar morph): sengaja,
  tak diubah.
- #5 Android nav (dibatalkan), #7 profil (ditunda), warm handoff.
- Durasi morph 260/220ms: tidak diubah.

## Testing

`flutter_app/test/widgets/scaled_video_feed_route_test.dart` (baru atau perluas):

- **Geometri anti-melar**: pump route dengan origin rect ber-aspek ≠ layar,
  pada progress tengah verifikasi child media (`OverflowBox` inner) berukuran =
  `screenSize` (konstan), sementara `ClipRect`/`Positioned` = lerp
  origin→fullscreen. Membuktikan media tak diregangkan.
- **Radius & opacity dari t**: pada t tengah, radius = `radius0*(1-t)` dan
  opacity crossfade = `Interval(0.55,1).transform(t)` (tak ada objek
  CurvedAnimation duplikat).

`flutter_app/test/widgets/feed_comment_sheet_*_test.dart` (atau baru):

- **Simetri #6**: `FeedCommentMediaFrame` memakai `Curves.easeOutCubic` baik
  saat `open:true` maupun `open:false`.

## Berkas tersentuh

- `flutter_app/lib/widgets/scaled_video_feed_route.dart` (#2, #3, #4).
- `flutter_app/lib/widgets/feed_comment_sheet.dart` (#6, satu baris kurva).
- Test terkait di atas.

## Verifikasi akhir

Device-verify: tap video (Detail Produk & Postingan) → morph membesar tanpa
media melar, framing mulus ke fullscreen tanpa lompatan; buka/tutup sheet
komentar terasa simetris.
