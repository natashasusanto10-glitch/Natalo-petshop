import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: child),
      ),
    );

/// Sama seperti [_wrap] tapi memaksa nilai OS `disableAnimations` — jalur
/// yang dibaca `MotionPrefs.shouldReduce`.
Widget _wrapMotion(Widget child, {required bool reduce}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: child),
        ),
      ),
    );

ScaleTransition _pulseOf(WidgetTester tester, String semanticLabel) {
  return tester.widget<ScaleTransition>(
    find
        .descendant(
          of: find.bySemanticsLabel(semanticLabel),
          matching: find.byType(ScaleTransition),
        )
        .first,
  );
}

void main() {
  testWidgets('menampilkan angka like/comment/share', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 128,
      liked: false,
      commentCount: 14,
      shareCount: 6,
    )));
    expect(find.text('128'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('count 0 disembunyikan (label baru muncul saat >0)',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 0,
      liked: false,
      commentCount: 0,
      shareCount: 0,
    )));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('format angka ribuan pakai K', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1500,
      liked: false,
      commentCount: 0,
      shareCount: 0,
    )));
    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('callback null tidak crash saat tap (mode pratinjau)',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1,
      liked: true,
      commentCount: 1,
      shareCount: 1,
    )));
    await tester.tap(find.text('1').first);
    await tester.pump();
  });

  testWidgets('bookmark is visible, accessible, and invokes save',
      (tester) async {
    var saveTaps = 0;
    await tester.pumpWidget(_wrap(FeedActionRail(
      likeCount: 1,
      liked: false,
      commentCount: 1,
      shareCount: 1,
      onSave: () => saveTaps++,
    )));

    expect(find.byType(Tooltip), findsNothing);
    expect(find.bySemanticsLabel('Simpan postingan'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Simpan postingan'));
    expect(saveTaps, 1);
  });

  testWidgets('saved bookmark exposes remove action', (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 0,
      liked: false,
      commentCount: 0,
      shareCount: 0,
      saved: true,
    )));

    expect(find.byType(Tooltip), findsNothing);
    expect(find.bySemanticsLabel('Hapus dari tersimpan'), findsOneWidget);
  });

  testWidgets('five actions use 6dp gaps and fit a 274dp compact rail',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedActionRail(
      likeCount: 1,
      liked: false,
      commentCount: 1,
      shareCount: 1,
    )));

    expect(tester.getSize(find.byType(FeedActionRail)).height, 274);

    final likeRect = tester.getRect(find.bySemanticsLabel('Sukai'));
    final commentRect = tester.getRect(find.bySemanticsLabel('Komentar'));
    final shareRect = tester.getRect(find.bySemanticsLabel('Bagikan'));
    expect(commentRect.top - likeRect.bottom, 6);
    expect(shareRect.top - commentRect.bottom, 6);
  });

  group('reduce-motion', () {
    testWidgets(
        'motion normal: pulse BERJALAN saat like (kontrol — membuktikan '
        'gate benar-benar mematikan sesuatu, bukan no-op)', (tester) async {
      await tester.pumpWidget(_wrapMotion(
        FeedActionRail(
          likeCount: 3,
          liked: false,
          commentCount: 0,
          shareCount: 0,
          onLike: () {},
        ),
        reduce: false,
      ));

      expect(_pulseOf(tester, 'Sukai').scale.value, 1.0);
      await tester.tap(find.bySemanticsLabel('Sukai'));
      // pump() pertama menyalakan ticker (elapsed 0); pump kedua baru
      // memajukan waktu. Tanpa ini nilai selalu terbaca 1.0.
      await tester.pump();
      // 80ms masuk ke fase membesar (durasi total 180ms, puncak 1.18).
      await tester.pump(const Duration(milliseconds: 80));
      expect(_pulseOf(tester, 'Sukai').scale.value, greaterThan(1.0));

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('reduce-motion: pulse TIDAK berjalan (skala tetap 1.0)',
        (tester) async {
      await tester.pumpWidget(_wrapMotion(
        FeedActionRail(
          likeCount: 3,
          liked: false,
          commentCount: 0,
          shareCount: 0,
          onLike: () {},
        ),
        reduce: true,
      ));

      await tester.tap(find.bySemanticsLabel('Sukai'));
      // Pola pump identik dengan test kontrol di atas — kalau pulse jalan,
      // nilainya PASTI sudah >1 di titik ini (terbukti oleh test kontrol).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_pulseOf(tester, 'Sukai').scale.value, 1.0);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
        'reduce-motion: AKSI tetap jalan — onLike/onSave tetap dipanggil '
        '(gerak dimatikan, fungsi tidak)', (tester) async {
      var likes = 0;
      var saves = 0;
      await tester.pumpWidget(_wrapMotion(
        FeedActionRail(
          likeCount: 3,
          liked: false,
          commentCount: 0,
          shareCount: 0,
          onLike: () => likes++,
          onSave: () => saves++,
        ),
        reduce: true,
      ));

      await tester.tap(find.bySemanticsLabel('Sukai'));
      await tester.tap(find.bySemanticsLabel('Simpan postingan'));
      await tester.pump();

      expect(likes, 1);
      expect(saves, 1);
    });
  });
}
