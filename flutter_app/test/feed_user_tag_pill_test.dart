import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/widgets/feed_tagged_users_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/feed_user_tag_pill.dart';

void main() {
  const photo = Size(300, 400);
  const pill = Size(80, 28);

  test('anchor tengah → pill di bawah anchor, panah di atas pill', () {
    final p = placeTagPill(
        anchor: const Offset(150, 200), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isFalse);
    expect(p.topLeft.dx, 150 - 40); // center horizontal di anchor
    expect(p.topLeft.dy, greaterThan(200)); // badan di bawah titik
  });

  test('anchor dekat tepi kanan → badan di-clamp tetap utuh', () {
    final p = placeTagPill(
        anchor: const Offset(298, 200), pillSize: pill, photoSize: photo);
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
  });

  test('anchor dekat tepi bawah → flip: panah di bawah pill', () {
    final p = placeTagPill(
        anchor: const Offset(150, 396), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isTrue);
    expect(p.topLeft.dy + pill.height, lessThanOrEqualTo(photo.height));
  });

  test('anchor dekat tepi kiri → clamp kiri', () {
    final p = placeTagPill(
        anchor: const Offset(2, 200), pillSize: pill, photoSize: photo);
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
  });

  test('anchor pojok kanan-bawah → clamp x dan y sekaligus + flip', () {
    final p = placeTagPill(
        anchor: const Offset(299, 399), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isTrue);
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
    expect(p.topLeft.dy, greaterThanOrEqualTo(0));
  });

  test('anchor pojok kiri-atas → clamp x dan y, tidak flip', () {
    final p = placeTagPill(
        anchor: const Offset(1, 1), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isFalse);
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
    expect(p.topLeft.dy, greaterThanOrEqualTo(0));
  });

  test('anchor tepat di tengah foto persis 300x400', () {
    final p = placeTagPill(
        anchor: const Offset(150, 200), pillSize: pill, photoSize: photo);
    // sanity: hasil topLeft selalu dalam batas foto
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
    expect(p.topLeft.dy, greaterThanOrEqualTo(0));
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
  });

  test('pill lebih lebar dari foto tetap tidak crash (clamp aman)', () {
    final p = placeTagPill(
        anchor: const Offset(5, 5),
        pillSize: const Size(500, 28),
        photoSize: photo);
    expect(p.topLeft.dx.isFinite, isTrue);
  });

  // ── fittedPhotoRect (final review Spec B fix — koordinat tag drift) ──

  group('fittedPhotoRect', () {
    test('aspect ratio SAMA dengan container → no-op, isi penuh container',
        () {
      const container = Size(300, 400);
      final rect = fittedPhotoRect(container, 300 / 400, BoxFit.contain);
      expect(rect, const Rect.fromLTWH(0, 0, 300, 400));
    });

    test(
        'foto portrait (9:16) di container landscape → letterbox KIRI-KANAN, '
        'tinggi = tinggi container', () {
      const container = Size(400, 200);
      const aspect = 9 / 16;
      final rect = fittedPhotoRect(container, aspect, BoxFit.contain);
      expect(rect.height, 200);
      expect(rect.width, closeTo(200 * aspect, 0.0001));
      // Center secara horizontal.
      expect(rect.left, closeTo((400 - rect.width) / 2, 0.0001));
      expect(rect.top, 0);
      // Rect harus di dalam batas container.
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(400));
    });

    test(
        'foto landscape (16:9) di container portrait → letterbox '
        'ATAS-BAWAH, lebar = lebar container', () {
      const container = Size(300, 600);
      const aspect = 16 / 9;
      final rect = fittedPhotoRect(container, aspect, BoxFit.contain);
      expect(rect.width, 300);
      expect(rect.height, closeTo(300 / aspect, 0.0001));
      expect(rect.top, closeTo((600 - rect.height) / 2, 0.0001));
      expect(rect.left, 0);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(600));
    });

    test('BoxFit.cover → SELALU isi penuh container, apa pun aspect ratio-nya',
        () {
      const container = Size(300, 400);
      final coverPortrait = fittedPhotoRect(container, 9 / 16, BoxFit.cover);
      final coverLandscape = fittedPhotoRect(container, 16 / 9, BoxFit.cover);
      expect(coverPortrait, Offset.zero & container);
      expect(coverLandscape, Offset.zero & container);
    });

    test('aspect ratio near-zero (foto sangat sempit) tidak crash/NaN', () {
      const container = Size(300, 400);
      final rect = fittedPhotoRect(container, 0.0001, BoxFit.contain);
      expect(rect.width.isFinite, isTrue);
      expect(rect.height.isFinite, isTrue);
      expect(rect.width, greaterThan(0));
      expect(rect.height, 400); // container lebih lebar relatif → letterbox L/R
    });

    test('aspect ratio sangat besar (foto sangat lebar/pendek) tidak crash',
        () {
      const container = Size(300, 400);
      final rect = fittedPhotoRect(container, 5000, BoxFit.contain);
      expect(rect.width.isFinite, isTrue);
      expect(rect.height.isFinite, isTrue);
      expect(rect.width, 300); // letterbox atas-bawah
      expect(rect.height, greaterThan(0));
    });

    test('aspectRatio <= 0 → fallback container penuh (tidak crash)', () {
      const container = Size(300, 400);
      expect(fittedPhotoRect(container, 0, BoxFit.contain),
          Offset.zero & container);
      expect(fittedPhotoRect(container, -1, BoxFit.contain),
          Offset.zero & container);
    });

    test('aspectRatio NaN/Infinity → fallback container penuh', () {
      const container = Size(300, 400);
      expect(fittedPhotoRect(container, double.nan, BoxFit.contain),
          Offset.zero & container);
      expect(fittedPhotoRect(container, double.infinity, BoxFit.contain),
          Offset.zero & container);
    });

    test('container kosong (width/height 0) → fallback tanpa crash', () {
      final rect = fittedPhotoRect(Size.zero, 9 / 16, BoxFit.contain);
      expect(rect, Rect.zero);
      final rectNegative =
          fittedPhotoRect(const Size(-10, 400), 9 / 16, BoxFit.contain);
      expect(rectNegative.width.isFinite, isTrue);
    });

    test('rect hasil SELALU berada dalam batas container (sanity, contain)',
        () {
      for (final aspect in [0.2, 0.5625, 1.0, 1.778, 3.0]) {
        const container = Size(320, 480);
        final rect = fittedPhotoRect(container, aspect, BoxFit.contain);
        expect(rect.left, greaterThanOrEqualTo(-0.001));
        expect(rect.top, greaterThanOrEqualTo(-0.001));
        expect(rect.right, lessThanOrEqualTo(container.width + 0.001));
        expect(rect.bottom, lessThanOrEqualTo(container.height + 0.001));
      }
    });
  });

  // ── Round-trip composer↔viewer (final review Spec B fix) ──
  //
  // Composer (feed_tag_people_screen.dart _onPhotoTapUp) menulis fraksi:
  //   fx = (tap.dx - rect.left) / rect.width
  // Viewer (feed_screen.dart LayoutBuilder → FeedTaggedUsersOverlay) baca
  // balik fraksi jadi piksel dengan photoSize=rect.size DI DALAM Positioned
  // yang di-offset rect.topLeft, jadi posisi absolut = rect.topLeft +
  // fraksi*rect.size — persis kebalikan formula composer. Group ini
  // membuktikan KEDUANYA konsisten untuk skenario letterbox nyata, dengan
  // container+aspectRatio SAMA persis di kedua sisi.
  group('round-trip composer -> viewer (letterbox tidak drift)', () {
    test(
        'fraksi hasil tap composer, direkonstruksi via fittedPhotoRect yang '
        'SAMA, mendarat tepat di titik tap asli (bukan posisi naif '
        'container)', () {
      const container = Size(400, 750); // area komposer portrait-ish
      const aspectRatio = 2.0; // foto landscape 2:1
      final rect = fittedPhotoRect(container, aspectRatio, BoxFit.contain);
      // Letterbox atas-bawah signifikan untuk kombinasi ini.
      expect(rect.width, container.width);
      expect(rect.height, lessThan(container.height));

      // Titik tap dekat tepi ATAS foto (bukan tepi container) — kasus
      // paling parah drift-nya di bug lama.
      final tap = rect.topLeft + const Offset(40, 5);

      // Composer capture — formula PERSIS _onPhotoTapUp.
      final fx = ((tap.dx - rect.left) / rect.width).clamp(0.0, 1.0);
      final fy = ((tap.dy - rect.top) / rect.height).clamp(0.0, 1.0);

      // Viewer render — formula PERSIS _positionedPill + Positioned offset
      // rect.topLeft di feed_screen.dart.
      final reconstructed =
          Offset(rect.left + fx * rect.width, rect.top + fy * rect.height);

      expect(reconstructed.dx, closeTo(tap.dx, 0.001));
      expect(reconstructed.dy, closeTo(tap.dy, 0.001));

      // Kontras dengan bug LAMA: fraksi naif (relatif CONTAINER penuh,
      // bukan rect foto) berbeda jauh dari fraksi yang benar — buktikan
      // fix ini betulan berarti untuk skenario letterbox signifikan ini
      // (test akan gagal kalau seseorang meregresi balik ke container
      // mentah).
      final naiveFy = tap.dy / container.height;
      expect((naiveFy - fy).abs(), greaterThan(0.1));
    });

    testWidgets(
        'viewer widget SUNGGUHAN (FeedTaggedUsersOverlay, dibungkus persis '
        'seperti feed_screen.dart) merender pill dekat anchor foto yang '
        'benar, bukan container mentah', (tester) async {
      const container = Size(400, 750);
      const aspectRatio = 2.0;
      final rect = fittedPhotoRect(container, aspectRatio, BoxFit.contain);
      final tap = rect.topLeft + const Offset(40, 5);
      final fx = ((tap.dx - rect.left) / rect.width).clamp(0.0, 1.0);
      final fy = ((tap.dy - rect.top) / rect.height).clamp(0.0, 1.0);

      // Bungkus FeedTaggedUsersOverlay PERSIS seperti feed_screen.dart:
      // Positioned(rect) di dalam Stack seukuran container, photoSize:
      // rect.size (bukan container).
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: container.width,
            height: container.height,
            child: Stack(
              children: [
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: FeedTaggedUsersOverlay(
                    tags: [
                      FeedTaggedUser(
                        userId: 'u1',
                        username: 'budi',
                        name: 'Budi',
                        mediaIndex: 0,
                        x: fx,
                        y: fy,
                      ),
                    ],
                    visible: true,
                    photoSize: rect.size,
                    onTapUser: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('budi'), findsOneWidget);
      // Pill body TIDAK boleh muncul jauh di dalam letterbox (mis. dekat
      // dasar container, y > rect.bottom + toleransi) — sanity kasar bahwa
      // overlay dipetakan ke area foto, bukan container penuh.
      final pillTop = tester.getTopLeft(find.text('budi')).dy;
      expect(pillTop, lessThanOrEqualTo(rect.bottom + 40));
      expect(pillTop, greaterThanOrEqualTo(rect.top - 40));
    });
  });
}
