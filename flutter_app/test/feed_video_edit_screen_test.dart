import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_video_edit_screen.dart';

void main() {
  const draft = FeedCreatePostDraft(
    localVideoPath: '/nonexistent/v.mp4', // init controller gagal di test env → error state
    originalDuration: Duration(seconds: 44),
  );

  Widget wrap() => const MaterialApp(home: FeedVideoEditScreen(draft: draft));

  testWidgets('chrome dasar: judul, back, next, pill Sampul & Potong',
      (tester) async {
    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Edit Video'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.text('Sampul'), findsOneWidget);
    expect(find.text('Potong'), findsOneWidget);
  });

  testWidgets('durasi <=60s: panel timeline tersembunyi, Potong menampilkannya',
      (tester) async {
    await tester.pumpWidget(wrap());
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsNothing);
    await tester.tap(find.text('Potong'));
    for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsOneWidget);
  });

  testWidgets('durasi >60s: timeline langsung tampil', (tester) async {
    const long = FeedCreatePostDraft(
      localVideoPath: '/nonexistent/v.mp4',
      originalDuration: Duration(seconds: 76),
    );
    await tester.pumpWidget(const MaterialApp(home: FeedVideoEditScreen(draft: long)));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsOneWidget);
  });

  testWidgets('durasi 60.5s dianggap >60s: timeline langsung tampil',
      (tester) async {
    const d = FeedCreatePostDraft(
      localVideoPath: '/nonexistent/v.mp4',
      originalDuration: Duration(milliseconds: 60500),
    );
    await tester.pumpWidget(const MaterialApp(home: FeedVideoEditScreen(draft: d)));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 80)); }
    expect(find.text('Geser pegangan untuk memangkas video'), findsOneWidget);
  });
}
