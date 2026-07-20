import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/services/api_client.dart';
import 'package:natalo_petshop_flutter/widgets/notification_reply_composer.dart';

FeedComment _comment({String? username = 'asiong'}) => FeedComment(
      id: 'c1',
      postId: 'p1',
      content: 'halo',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.now(),
      viewerLiked: false,
      author: FeedAuthor(id: 'u1', name: 'Asiong', username: username),
    );

Future<void> _open(
  WidgetTester tester, {
  required FeedComment comment,
  required CommentReplyPoster poster,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showNotificationReplyComposer(
              context,
              comment: comment,
              feedPostId: 'p1',
              poster: poster,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('prefill @username + label Membalas', (tester) async {
    await _open(
      tester,
      comment: _comment(),
      poster: (_, {required content, parentCommentId}) async {},
    );
    expect(find.text('Membalas @asiong'), findsOneWidget);
    expect(find.text('@asiong '), findsOneWidget); // isi TextField
  });

  testWidgets('kirim memanggil poster dgn parentCommentId benar + pop',
      (tester) async {
    String? gotPost;
    String? gotParent;
    String? gotContent;
    await _open(
      tester,
      comment: _comment(),
      poster: (postId, {required content, parentCommentId}) async {
        gotPost = postId;
        gotContent = content;
        gotParent = parentCommentId;
      },
    );
    await tester.enterText(find.byType(TextField), '@asiong mantap');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(gotPost, 'p1');
    expect(gotParent, 'c1');
    expect(gotContent, '@asiong mantap');
    expect(find.text('Balasan terkirim'), findsOneWidget);
    expect(find.byType(NotificationReplyComposer), findsNothing); // sudah pop
  });

  testWidgets('kirim gagal (bukan 404) → composer tetap terbuka + snackbar',
      (tester) async {
    await _open(
      tester,
      comment: _comment(),
      poster: (_, {required content, parentCommentId}) async =>
          throw const ApiException('boom', statusCode: 500),
    );
    await tester.enterText(find.byType(TextField), 'coba');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReplyComposer), findsOneWidget); // masih ada
    expect(find.text('Gagal mengirim balasan. Coba lagi.'), findsOneWidget);
  });

  testWidgets('kirim 404 (post dihapus saat kirim) → composer ditutup',
      (tester) async {
    await _open(
      tester,
      comment: _comment(),
      poster: (_, {required content, parentCommentId}) async =>
          throw const ApiException('gone', statusCode: 404),
    );
    await tester.enterText(find.byType(TextField), 'coba');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReplyComposer), findsNothing); // ditutup
    expect(find.text('Postingan sudah dihapus.'), findsOneWidget);
  });

  testWidgets('tombol kirim disabled saat kosong', (tester) async {
    await _open(
      tester,
      comment: _comment(username: null), // tanpa username → prefill kosong
      poster: (_, {required content, parentCommentId}) async {},
    );
    // Tap send saat kosong tidak crash / tidak memanggil poster (tak ada snackbar terkirim).
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(find.text('Balasan terkirim'), findsNothing);
    expect(find.text('Membalas Asiong'), findsOneWidget); // fallback tanpa @
  });
}
