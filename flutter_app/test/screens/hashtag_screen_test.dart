import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/hashtag_screen.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

FeedPost post(String id, String author) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO_CAROUSEL',
      'thumbnailUrl': 'placeholder-$id',
      'author': {'id': 'u-$author', 'name': author},
      'createdAt': '2026-07-23T00:00:00.000Z',
    });

Future<void> pump(
  WidgetTester tester,
  Future<HashtagPageResult> Function(String, {String? cursor}) fetcher,
) async {
  await tester.pumpWidget(MaterialApp(
    home: HashtagScreen(name: 'kucing', fetcher: fetcher),
  ));
  await tester.pump(); // resolve future
  await tester.pump();
}

void main() {
  testWidgets('judul #kucing + hitungan + grid multi-author', (tester) async {
    await pump(
      tester,
      (name, {cursor}) async => HashtagPageResult(
        name: name,
        postCount: 2,
        posts: [post('p1', 'Budi'), post('p2', 'Sari')],
        nextCursor: null,
      ),
    );
    expect(find.text('#kucing'), findsOneWidget);
    expect(find.textContaining('2 postingan'), findsOneWidget);
  });

  testWidgets('kosong → copy empty state persis spec', (tester) async {
    await pump(
      tester,
      (name, {cursor}) async => HashtagPageResult(
          name: name, postCount: 0, posts: const [], nextCursor: null),
    );
    expect(find.text('Belum ada postingan dengan tag ini.'), findsOneWidget);
  });

  testWidgets('error → BUKAN empty state; ada tombol coba lagi yang retry',
      (tester) async {
    var calls = 0;
    await pump(tester, (name, {cursor}) async {
      calls++;
      if (calls == 1) throw Exception('network');
      return HashtagPageResult(
          name: name,
          postCount: 1,
          posts: [post('p1', 'Budi')],
          nextCursor: null);
    });
    expect(find.text('Belum ada postingan dengan tag ini.'), findsNothing);
    final retry = find.textContaining(
        'oba lagi'); // "Coba lagi"/"Coba Lagi" sesuai widget standar
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('1 postingan'), findsOneWidget);
  });
}
