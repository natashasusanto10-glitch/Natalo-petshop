import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/screens/feed_new_post_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

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
}
