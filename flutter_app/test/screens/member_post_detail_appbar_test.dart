// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/widgets/liquid_glass.dart';

FeedPost _photoPost({
  String id = 'appbar-test-photo',
  bool following = false,
}) =>
    FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO',
      'author': {
        'id': 'author-1',
        'name': 'Rani',
        'role': 'CUSTOMER',
        'isFollowing': following,
      },
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

void main() {
  testWidgets(
      'header is a transparent overlay (no Scaffold.appBar) with LiquidGlass back button',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MemberPostDetailScreen(post: _photoPost())),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Custom Positioned overlay, BUKAN Scaffold.appBar (lihat komentar di
    // member_post_detail_screen.dart build() — AppBar bawaan menyerap tap
    // di seluruh lebar toolbar walau transparan, menutupi header per-post).
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Postingan'), findsOneWidget);
    // Back button ala IG: chevron "<" polos tanpa pill kaca/border.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

    // Frosted-tipis di strip header (BackdropFilter) — konten tembus tapi
    // teks kebaca (paritas IG).
    expect(find.byType(BackdropFilter), findsWidgets);

    // Media post pertama mulai DI BAWAH header — ListView diberi top padding
    // (status bar + toolbar) supaya tidak "over ke atas" / kepotong.
    final listPadding = tester
        .widget<ListView>(find.byType(ListView))
        .padding as EdgeInsets;
    expect(listPadding.top, greaterThan(0));
  });

  testWidgets(
      'tapping the per-post header still works when it is the first post '
      '(regression: transparent overlay must not swallow its taps)',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'appbar-header-tap-regression',
      'slug': 'appbar-header-tap-regression',
      'kind': 'PHOTO',
      'author': {
        'id': 'author-1',
        'name': 'Rani',
        'username': 'rani_official',
        'role': 'CUSTOMER',
      },
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // .first = _PostAuthorRow's name (ListView content, added before the
    // header overlay in the Stack) — a real hit-test regression (header
    // swallowing the tap) throws WidgetController's "does not hit test"
    // warning here, same as it did before the fix.
    await tester.tap(find.text('Rani').first);
    await tester.pumpAndSettle();

    expect(find.byType(PublicProfileScreen), findsOneWidget);
  });

  testWidgets(
      'Ikuti chip shown when viewing another user\'s post, hidden for own',
      (tester) async {
    final post = _photoPost(id: 'appbar-test-other');

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Ikuti'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(post: post, isOwner: true),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Mengikuti'), findsNothing);
  });

  testWidgets('Ikuti chip shows Mengikuti when already following',
      (tester) async {
    final post = _photoPost(id: 'appbar-test-following', following: true);

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Mengikuti'), findsOneWidget);
  });

  testWidgets(
      'authorIsFollowing override wins over post.author (profile payload '
      'has no author object — regression: chip stuck on "Ikuti")',
      (tester) async {
    // Simulasi item /api/u/{username}: TIDAK ada objek author sama sekali
    // → FeedAuthor default (id '', isFollowing false).
    final post = FeedPost.fromJson({
      'id': 'appbar-profile-shape',
      'slug': 'appbar-profile-shape',
      'kind': 'PHOTO',
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
        authorId: 'author-1',
        authorIsFollowing: true,
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Mengikuti'), findsOneWidget);
    expect(find.text('Ikuti'), findsNothing);
  });

  testWidgets('chip hidden when author id unresolvable (empty)',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'appbar-no-author-id',
      'slug': 'appbar-no-author-id',
      'kind': 'PHOTO',
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // follow('') pasti gagal — lebih baik chip tak tampil.
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Mengikuti'), findsNothing);
  });
}
