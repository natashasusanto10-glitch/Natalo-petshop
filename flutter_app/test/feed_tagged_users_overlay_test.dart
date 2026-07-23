import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/widgets/feed_tagged_users_overlay.dart';

void main() {
  const tag = FeedTaggedUser(
      userId: 'u1', username: 'budi', name: 'Budi', mediaIndex: 0, x: 0.5, y: 0.5);

  testWidgets('visible=false → pill tak dirender', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedTaggedUsersOverlay(
        tags: const [tag],
        visible: false,
        photoSize: const Size(300, 400),
        onTapUser: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('budi'), findsNothing);
  });

  testWidgets('visible=true → pill muncul; tap → callback', (tester) async {
    FeedTaggedUser? tapped;
    await tester.pumpWidget(MaterialApp(
      home: FeedTaggedUsersOverlay(
        tags: const [tag],
        visible: true,
        photoSize: const Size(300, 400),
        onTapUser: (t) => tapped = t,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('budi'));
    expect(tapped?.userId, 'u1');
  });

  testWidgets('badge tampil dengan ikon orang', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FeedTaggedBadge(onTap: () {})),
    ));
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
