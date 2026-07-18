// T3 — verifikasi entry point "..." → "Edit caption" menavigasi ke
// MemberPostEditScreen (route '/member/postingan-edit') alih-alih membuka
// sheet _EditCaptionSheet lama (sudah dihapus). Rendering MemberPostDetailScreen
// penuh disini pakai fixture PHOTO_CAROUSEL (bukan video) supaya tidak butuh
// fake video_player platform — pola sama seperti
// member_post_detail_comment_identity_test.dart. Navigasi ditangkap lewat
// NavigatorObserver + onGenerateRoute spy (bukan me-mount MemberPostEditScreen
// asli, yang butuh setup network/PATCH tersendiri di luar cakupan test ini).
//
// PENTING: onGenerateRoute di bawah ini adalah spy LOKAL test — bukan router
// asli main.dart (main.dart merangkai onGenerateRoute inline di dalam builder
// MaterialApp, bukan sebagai top-level/static function, jadi tak bisa
// di-import langsung ke test). Nilai '/member/postingan-edit' HARUS disalin
// manual dari registrasi rute asli di lib/main.dart (cari case
// "'/member/postingan-edit' when settings.arguments is FeedPost" — saat ini
// main.dart:418). Jika lib/main.dart mengubah string rute itu, update juga
// literal di sini SUPAYA test ini tetap jadi guard yang jujur — JANGAN
// menyalin literal yang dipakai oleh kode produksi (member_post_detail_screen
// .dart) tanpa mengecek dulu ke main.dart, karena itulah yang membuat versi
// sebelumnya lolos walau salah ('/member/post-edit' tidak pernah terdaftar).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

FeedPost _fakePhotoPost({String id = 'post-edit-nav'}) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO_CAROUSEL',
      'caption': 'Caption asli',
      'mediaItems': [
        {
          'id': 'media-1',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'likeCount': 0,
      'commentCount': 0,
      'shareCount': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

void main() {
  testWidgets(
    '"..." → Edit caption menavigasi ke /member/postingan-edit (sesuai main.dart) dengan post yang benar',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final post = _fakePhotoPost();
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          // Literal '/member/postingan-edit' disalin manual dari main.dart
          // (lihat komentar file di atas) — SENGAJA independen dari string
          // yang dipush member_post_detail_screen.dart, supaya test ini gagal
          // kalau produksi push nama rute yang tak terdaftar di main.dart.
          onGenerateRoute: (settings) {
            if (settings.name == '/member/postingan-edit') {
              return MaterialPageRoute<bool>(
                settings: settings,
                builder: (_) => const SizedBox(),
              );
            }
            return null;
          },
          home: MemberPostDetailScreen(post: post, isOwner: true),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Buka menu "...".
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap "Edit caption" di sheet menu.
      expect(find.text('Edit caption'), findsOneWidget);
      await tester.tap(find.text('Edit caption'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final editRoutes = observer.pushed
          .where((r) => r.settings.name == '/member/postingan-edit')
          .toList();
      expect(editRoutes, hasLength(1),
          reason:
              'Edit caption harus push route /member/postingan-edit persis '
              'sekali (sesuai registrasi main.dart), bukan lagi '
              'showModalBottomSheet _EditCaptionSheet lokal ataupun nama '
              'rute lain yang tak terdaftar');

      final arg = editRoutes.single.settings.arguments;
      expect(arg, isA<FeedPost>(),
          reason: 'argumen route harus FeedPost sesuai kontrak main.dart');
      expect((arg as FeedPost).id, post.id);
    },
  );
}
