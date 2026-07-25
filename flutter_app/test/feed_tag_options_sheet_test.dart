import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/widgets/feed_tag_options_sheet.dart';
import 'package:natalo_petshop_flutter/widgets/official_brand_avatar.dart';
import 'package:natalo_petshop_flutter/widgets/profile_avatar.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required VoidCallback onRemoved,
    VoidCallback? onRemoveFailed,
    ValueChanged<bool>? onHiddenChanged,
    bool hidden = false,
    Future<void> Function(String)? removeTag,
    Future<void> Function(String, bool)? setHidden,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showFeedTagOptionsSheet(
            context,
            postId: 'p1',
            hidden: hidden,
            onRemoved: onRemoved,
            onRemoveFailed: onRemoveFailed,
            onHiddenChanged: onHiddenChanged ?? (_) {},
            removeTag: removeTag ?? (_) async {},
            setHidden: setHidden ?? (_, __) async {},
          ),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Hapus saya: konfirmasi ringan lalu onRemoved optimistic',
      (tester) async {
    var removed = false;
    final networkDone = Completer<void>();
    await openSheet(
      tester,
      onRemoved: () => removed = true,
      removeTag: (_) => networkDone.future, // network belum selesai
    );
    await tester.tap(find.text('Hapus saya dari post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus')); // tombol konfirmasi
    await tester.pump();
    expect(removed, isTrue); // TANPA menunggu networkDone → optimistic
    networkDone.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('toggle Sembunyikan memanggil setHidden(true)', (tester) async {
    bool? sent;
    await openSheet(
      tester,
      onRemoved: () {},
      setHidden: (_, hidden) async => sent = hidden,
    );
    await tester.tap(find.text('Sembunyikan dari profil saya'));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
  });

  testWidgets('hidden=true → label jadi Tampilkan di profil saya',
      (tester) async {
    await openSheet(tester, onRemoved: () {}, hidden: true);
    expect(find.text('Tampilkan di profil saya'), findsOneWidget);
  });

  testWidgets(
      'Hapus saya gagal: onRemoveFailed dipanggil (rollback) + toast galat',
      (tester) async {
    var removed = false;
    var removeFailed = false;
    final networkDone = Completer<void>();
    await openSheet(
      tester,
      onRemoved: () => removed = true,
      onRemoveFailed: () => removeFailed = true,
      removeTag: (_) => networkDone.future,
    );
    await tester.tap(find.text('Hapus saya dari post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pump(); // onRemoved optimistic — sinkron sebelum network
    expect(removed, isTrue);
    expect(removeFailed, isFalse); // network belum selesai → belum rollback
    networkDone.completeError(Exception('network error'));
    await tester.pump(); // biarkan await doRemove(postId) gagal + catch jalan
    expect(removeFailed, isTrue); // rollback diminta ke pemanggil
    expect(find.text('Gagal menghapus tag. Coba lagi.'), findsOneWidget);
    // Kuras timer auto-hide toast supaya tidak "pending" saat test selesai.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('toggle Sembunyikan gagal: rollback ke label semula + toast',
      (tester) async {
    final calls = <bool>[];
    final networkDone = Completer<void>();
    await openSheet(
      tester,
      onRemoved: () {},
      onHiddenChanged: calls.add,
      setHidden: (_, __) => networkDone.future,
    );
    await tester.tap(find.text('Sembunyikan dari profil saya'));
    await tester.pump(); // optimistic onHiddenChanged(true)
    expect(calls, [true]);
    networkDone.completeError(Exception('network error'));
    await tester.pump(); // biarkan await doSetHidden gagal + rollback jalan
    expect(calls, [true, false]); // rollback → onHiddenChanged(false)
    expect(find.text('Gagal menyimpan. Coba lagi.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('sheet video "Ditandai dalam video ini": daftar tagged users',
      (tester) async {
    final post = FeedPost(
      id: 'p1',
      slug: 'p1',
      videoUrl: 'https://example.com/v.mp4',
      author: const FeedAuthor(id: 'author1', name: 'Natalo Petshop'),
      createdAt: DateTime(2024),
      taggedUsers: const [
        FeedTaggedUser(userId: 'u1', username: 'andi', name: 'Andi'),
        FeedTaggedUser(userId: 'u2', username: 'budi', name: 'Budi'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showFeedTaggedUsersSheet(
            context,
            post: post,
            selfUserId: 'someone-else',
            onSelfRemoved: () {},
            onSelfHiddenChanged: (_) {},
          ),
          child: const Text('open video sheet'),
        );
      }),
    ));
    await tester.tap(find.text('open video sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Ditandai dalam video ini'), findsOneWidget);
    expect(find.text('Andi'), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);
  });

  testWidgets(
      'sheet video: akun official (nama sudah di-brand server) render logo '
      'brand lokal, BUKAN inisial (server null-kan foto asli admin)',
      (tester) async {
    final post = FeedPost(
      id: 'p1',
      slug: 'p1',
      videoUrl: 'https://example.com/v.mp4',
      author: const FeedAuthor(id: 'author1', name: 'Natalo Petshop'),
      createdAt: DateTime(2024),
      taggedUsers: const [
        // Server sudah substitusi name→kOfficialBrandName & photoUrl→null
        // untuk role ADMIN (brand-user.ts) — persis bentuk JSON asli.
        FeedTaggedUser(
          userId: 'admin1',
          username: 'natalopetshop',
          name: 'Natalo Petshop Official',
          profilePhotoUrl: null,
        ),
        FeedTaggedUser(userId: 'u2', username: 'budi', name: 'Budi'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showFeedTaggedUsersSheet(
            context,
            post: post,
            selfUserId: 'someone-else',
            onSelfRemoved: () {},
            onSelfHiddenChanged: (_) {},
          ),
          child: const Text('open video sheet'),
        );
      }),
    ));
    await tester.tap(find.text('open video sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Natalo Petshop Official'), findsOneWidget);
    expect(find.byType(OfficialBrandAvatar), findsOneWidget);
    // Baris lain (bukan official) tetap ProfileAvatar biasa.
    expect(find.byType(ProfileAvatar), findsOneWidget);
  });

  testWidgets(
      'sheet video: tap baris nama sendiri membuka sheet Opsi Tag yang sama',
      (tester) async {
    final post = FeedPost(
      id: 'p1',
      slug: 'p1',
      videoUrl: 'https://example.com/v.mp4',
      author: const FeedAuthor(id: 'author1', name: 'Natalo Petshop'),
      createdAt: DateTime(2024),
      taggedUsers: const [
        FeedTaggedUser(userId: 'self1', username: 'aku', name: 'Aku'),
        FeedTaggedUser(userId: 'other1', username: 'lain', name: 'Lain'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showFeedTaggedUsersSheet(
            context,
            post: post,
            selfUserId: 'self1',
            onSelfRemoved: () {},
            onSelfHiddenChanged: (_) {},
          ),
          child: const Text('open video sheet'),
        );
      }),
    ));
    await tester.tap(find.text('open video sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aku'));
    await tester.pumpAndSettle();
    // Video sheet pops lalu Opsi Tag (sheet yang sama dgn foto) terbuka —
    // TIDAK menyentuh feedService asli (tanpa injeksi removeTag/setHidden
    // di sini), jadi tap lanjutan ke "Hapus" sengaja tidak dites di sini
    // (sudah dicakup skenario optimistic/rollback di atas).
    expect(find.text('Opsi Tag'), findsOneWidget);
    expect(find.text('Hapus saya dari post'), findsOneWidget);
    expect(find.text('Sembunyikan dari profil saya'), findsOneWidget);
  });
}
