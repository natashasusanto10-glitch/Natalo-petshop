import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/screens/feed_new_post_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_upload_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('feed_new_post_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    // feedUploadStore adalah singleton global — reset supaya test lain
    // (dalam file ini atau ditambah nanti) tidak kebawa state upload dari
    // test hashtag-limit di bawah.
    feedUploadStore.clear();
  });

  List<File> makePhotoFiles(int count) {
    return List.generate(count, (i) {
      final file = File('${tempDir.path}${Platform.pathSeparator}slide_$i.jpg');
      file.writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, i]);
      return file;
    });
  }

  const videoDraft = FeedCreatePostDraft(
    localVideoPath: '/nonexistent/v.mp4',
    originalDuration: Duration(seconds: 30),
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FeedNewPostScreen(draft: NewPostMediaDraft.video(videoDraft)),
    ));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
  }

  testWidgets('bottom bar: Simpan Draft dan Bagikan berdampingan',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Simpan Draft'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
  });

  testWidgets('thumbnail video: pill Pratinjau + Ubah sampul', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Pratinjau'), findsOneWidget);
    expect(find.text('Ubah sampul'), findsOneWidget);
  });

  testWidgets('caption trigger tetap ada', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Tulis caption...'), findsOneWidget);
  });

  Future<void> pumpCarouselScreen(WidgetTester tester, List<File> files) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedNewPostScreen(draft: NewPostMediaDraft.photos(files)),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('carousel: strip slide tampil dengan 3 item saat >1 foto',
      (tester) async {
    final files = makePhotoFiles(3);
    await pumpCarouselScreen(tester, files);

    expect(find.byKey(const ValueKey('slide-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slide-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slide-2')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('carousel: tombol hapus slide mengurangi jumlah',
      (tester) async {
    final files = makePhotoFiles(3);
    await pumpCarouselScreen(tester, files);

    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slide-delete-0')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('1/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('slide-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('slide-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slide-2')), findsNothing);
  });

  testWidgets('carousel: hapus sampai 1 foto → tombol hapus hilang (min 1)',
      (tester) async {
    final files = makePhotoFiles(2);
    await pumpCarouselScreen(tester, files);

    // Strip hanya muncul kalau >1 foto — hapus salah satu dulu.
    await tester.tap(find.byKey(const ValueKey('slide-delete-0')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Tinggal 1 foto — strip carousel disembunyikan (bukan cuma tombol
    // hapus), karena strip hanya dirender saat _photoFiles.length > 1.
    expect(find.byKey(const ValueKey('slide-delete-0')), findsNothing);
    expect(find.byKey(const ValueKey('slide-0')), findsNothing);
  });

  testWidgets(
      'carousel: hapus slide sebelum slide aktif → slide aktif tetap dipertahankan',
      (tester) async {
    final files = makePhotoFiles(3);
    await pumpCarouselScreen(tester, files);

    // Swipe ke slide index 1 ("2/3") dulu.
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2/3'), findsOneWidget);

    // Hapus slide index 0 (di depan slide aktif) — slide aktif (dulu index
    // 1) harus tetap dipertahankan, sekarang jadi index 0 ("1/2"), bukan
    // ikut ke slide index 1 yang baru ("2/2").
    await tester.tap(find.byKey(const ValueKey('slide-delete-0')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('section Tag Produk Pernah Dibeli tersembunyi (flag off)',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Tag Produk Pernah Dibeli'), findsNothing);
  });

  testWidgets(
      'caption 6 hashtag (prefilled, tanpa lewat editor): tap Bagikan '
      'blokir upload + tampilkan error limit', (tester) async {
    // prefilledCaption meniru jalur "resume draft" — caption masuk ke
    // controller TANPA lewat FeedCaptionEditScreen (yang sudah house
    // validasi layer 1-nya sendiri). Ini persis skenario yang dijaga
    // recheck submit-time (layer 2) di `_upload()`.
    await tester.pumpWidget(const MaterialApp(
      home: FeedNewPostScreen(
        draft: NewPostMediaDraft.video(videoDraft),
        prefilledCaption: '#aa #bb #cc #dd #ee #ff',
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Tombol masih enabled (belum ada error) sebelum tap pertama.
    // skipOffstage: false — pesan error letaknya di bawah `_TagPeopleRow`
    // dalam ListView, di luar viewport test default, jadi harus dicari
    // termasuk elemen yang belum di-scroll ke layar.
    expect(
        find.text('Maksimal 5 hashtag per postingan.', skipOffstage: false),
        findsNothing);

    await tester.tap(find.text('Bagikan'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
        find.text('Maksimal 5 hashtag per postingan.', skipOffstage: false),
        findsOneWidget);
    expect(feedUploadStore.isUploading, isFalse);
    expect(feedUploadStore.activeTask, isNull);
  });
}
