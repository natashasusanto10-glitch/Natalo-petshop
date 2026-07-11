import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_cover_picker_screen.dart';

Uint8List _px() => Uint8List.fromList([137,80,78,71,13,10,26,10]); // dummy

void main() {
  Widget wrap() => MaterialApp(home: FeedCoverPickerScreen(
        videoPath: 'v.mp4',
        rangeStart: const Duration(seconds: 40),
        rangeSpan: const Duration(seconds: 20),
        currentCoverPath: null,
        frameExtractor: (p, t) async => _px(),
        coverGenerator: (p, t) async => '/tmp/cover-$t.jpg',
      ));

  testWidgets('header: judul, tombol tutup, tombol konfirmasi', (tester) async {
    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(find.text('Ubah Sampul'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Ambil dari galeri'), findsOneWidget);
  });

  testWidgets('konfirmasi pop dengan path dari coverGenerator', (tester) async {
    String? popped = 'sentinel';
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return ElevatedButton(
        onPressed: () async {
          popped = await Navigator.push<String>(context, MaterialPageRoute(
            builder: (_) => FeedCoverPickerScreen(
              videoPath: 'v.mp4',
              rangeStart: Duration.zero,
              rangeSpan: const Duration(seconds: 10),
              currentCoverPath: null,
              frameExtractor: (p, t) async => _px(),
              coverGenerator: (p, t) async => '/tmp/cover.jpg',
            )));
        },
        child: const Text('go'));
    })));
    await tester.tap(find.text('go'));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    await tester.tap(find.byIcon(Icons.check_rounded));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(popped, '/tmp/cover.jpg');
  });

  testWidgets(
      'hero preview pakai previewFrameExtractor hi-res, bukan frameExtractor filmstrip',
      (tester) async {
    final filmstripBytes = Uint8List.fromList([1, 1, 1]);
    final previewBytes = Uint8List.fromList([9, 9, 9]);
    final previewCallTimes = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: FeedCoverPickerScreen(
        videoPath: 'v.mp4',
        rangeStart: const Duration(seconds: 40),
        rangeSpan: const Duration(seconds: 20),
        currentCoverPath: null,
        frameExtractor: (p, t) async => filmstripBytes,
        previewFrameExtractor: (p, t) async {
          previewCallTimes.add(t);
          return previewBytes;
        },
        coverGenerator: (p, t) async => '/tmp/cover-$t.jpg',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Hero preview awal (initState) sudah pakai previewFrameExtractor —
    // BUKAN bytes filmstrip (frameExtractor).
    expect(previewCallTimes, isNotEmpty);
    final heroFinderInitial = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is MemoryImage &&
          identical((w.image as MemoryImage).bytes, previewBytes),
    );
    expect(heroFinderInitial, findsOneWidget);
    // Filmstrip tetap render frame low-res-nya sendiri (frameExtractor),
    // memastikan kedua extractor tidak tertukar.
    final filmstripFinder = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is MemoryImage &&
          identical((w.image as MemoryImage).bytes, filmstripBytes),
    );
    expect(filmstripFinder, findsWidgets);

    // Drag/tap filmstrip → hero refresh lewat previewFrameExtractor lagi
    // (dengan timestamp baru), bukan frameExtractor filmstrip.
    final callsBeforeDrag = previewCallTimes.length;
    final filmstripGesture = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onHorizontalDragEnd != null,
    );
    expect(filmstripGesture, findsOneWidget);
    await tester.tap(filmstripGesture);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(previewCallTimes.length, greaterThan(callsBeforeDrag));
    final heroFinderAfterDrag = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is MemoryImage &&
          identical((w.image as MemoryImage).bytes, previewBytes),
    );
    expect(heroFinderAfterDrag, findsOneWidget);
  });
}
