import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/new_post_user_tag.dart';
import 'package:natalo_petshop_flutter/screens/feed_post/feed_tag_people_screen.dart';

void main() {
  const tag = NewPostUserTag(
      userId: 'u1',
      username: 'budi',
      name: 'Budi',
      mediaIndex: 0,
      x: 0.5,
      y: 0.5);

  Future<void> pump(WidgetTester tester,
      {List<NewPostUserTag> initial = const []}) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedTagPeopleScreen(
        photoFiles: [File('test/assets/placeholder.png')],
        initialTags: initial,
        searchUsers: (q, {suggested = false}) async => const [],
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('judul, tombol selesai, dan hint tampil', (tester) async {
    await pump(tester);
    expect(find.text('Tandai Orang'), findsOneWidget);
    expect(find.text('Ketuk foto untuk menandai orang'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('initial tag dirender sebagai pill', (tester) async {
    await pump(tester, initial: const [tag]);
    expect(find.text('budi'), findsOneWidget);
  });

  testWidgets('tap pill → tombol X → hapus', (tester) async {
    await pump(tester, initial: const [tag]);
    await tester.tap(find.text('budi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('budi'), findsNothing);
  });

  testWidgets('tombol selesai pop dengan list tag', (tester) async {
    List<NewPostUserTag>? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<List<NewPostUserTag>>(
              MaterialPageRoute(
                builder: (_) => FeedTagPeopleScreen(
                  photoFiles: [File('test/assets/placeholder.png')],
                  initialTags: const [tag],
                  searchUsers: (q, {suggested = false}) async => const [],
                ),
              ),
            );
          },
          child: const Text('go'),
        );
      }),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(popped, hasLength(1));
  });
}
