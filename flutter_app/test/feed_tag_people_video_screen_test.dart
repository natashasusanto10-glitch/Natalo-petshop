import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/new_post_user_tag.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_tag_people_video_screen.dart';

void main() {
  const tag = NewPostUserTag(userId: 'u1', username: 'budi', name: 'Budi');

  testWidgets('daftar tag tampil + bisa hapus', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedTagPeopleVideoScreen(
        initialTags: const [tag],
        searchUsers: (q, {suggested = false}) async => const [],
      ),
    ));
    await tester.pump();
    expect(find.text('Tandai Orang'), findsOneWidget);
    expect(find.text('budi'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('budi'), findsNothing);
  });

  testWidgets('limit 20 → row tambah nonaktif + snackbar', (tester) async {
    final many = List.generate(
        20, (i) => NewPostUserTag(userId: 'u$i', username: 'user$i'));
    await tester.pumpWidget(MaterialApp(
      home: FeedTagPeopleVideoScreen(
        initialTags: many,
        searchUsers: (q, {suggested = false}) async => const [],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Tambah orang'));
    await tester.pump();
    expect(find.text('Maksimal 20 orang per postingan.'), findsOneWidget);
    // Bereskan timer auto-dismiss toast (bounded pump, bukan pumpAndSettle —
    // lihat gotcha flutter-widget-test-shimmer-hang).
    await tester.pump(const Duration(milliseconds: 2400));
  });
}
