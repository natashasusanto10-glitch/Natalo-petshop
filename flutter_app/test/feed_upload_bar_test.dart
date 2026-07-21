import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_upload_bar.dart';
import 'package:natalo_petshop_flutter/state/feed_upload_store.dart';

Widget _wrap() => const MaterialApp(
    home: Scaffold(backgroundColor: Colors.black, body: FeedUploadBar()));

FeedUploadTask _task(FeedUploadStatus s, {double progress = 0.4}) {
  // Semua kasus test pakai kind video (photoFiles kosong) — varian copy
  // foto/carousel diuji manual di device (butuh File nyata utk thumbnail).
  return FeedUploadTask(
    localId: 't1', kind: FeedUploadKind.video,
    status: s, progress: progress, createdAt: DateTime(2026),
  );
}

void main() {
  tearDown(() => feedUploadStore.clear());

  testWidgets('idle: bar tidak dirender', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byType(FeedUploadBar), findsOneWidget);
    expect(find.textContaining('diposting'), findsNothing);
  });

  testWidgets('preparing video: copy + spinner + tombol batal', (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.preparing));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sebentar ya, videomu lagi diposting…'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('waitingReview: copy terkirim (tanpa review), tanpa tombol batal',
      (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.waitingReview, progress: 1));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Terkirim! Sebentar lagi tayang'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('success video: copy diproses (auto-approve), tanpa tombol batal',
      (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.success, progress: 1));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Terkirim! Videomu lagi diproses, sebentar lagi tayang'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('failed: copy gagal + tombol Coba lagi', (tester) async {
    feedUploadStore.debugSetTask(_task(FeedUploadStatus.failed));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gagal mengunggah'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
  });

  testWidgets('carousel uploading: counter pakai done/total asli (n/n)',
      (tester) async {
    // Progress banded (0.05-0.85) tidak boleh dipakai untuk hitung n —
    // pastikan bar pakai photosDone/photosTotal asli dari store, bukan
    // round(progress*total) yang bisa drift / tidak pernah n/n.
    feedUploadStore.debugSetTask(FeedUploadTask(
      localId: 't-carousel',
      kind: FeedUploadKind.photo,
      status: FeedUploadStatus.uploading,
      progress: 0.85,
      photosDone: 8,
      photosTotal: 8,
      createdAt: DateTime(2026),
    ));
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Foto 8/8'), findsOneWidget);
  });
}
