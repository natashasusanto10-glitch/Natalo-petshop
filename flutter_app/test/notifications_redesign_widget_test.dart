import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';
import 'package:natalo_petshop_flutter/screens/notifications_screen.dart';
import 'package:natalo_petshop_flutter/widgets/official_brand_avatar.dart';
import 'package:natalo_petshop_flutter/widgets/profile_avatar.dart';

AppNotification _notif({
  String title = 'Feed kamu sudah tayang',
  String body = 'Postingan disetujui.',
  bool read = false,
  String? imageUrl,
  String? category,
}) =>
    AppNotification.fromApiJson({
      'id': 'n1',
      'title': title,
      'body': body,
      'type': 'info',
      if (category != null) 'category': category,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'createdAt':
          DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      'read': read,
    });

Future<void> _pumpRow(WidgetTester tester, AppNotification n) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotificationRow(notification: n, onTap: () {}),
      ),
    ),
  );
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  int unread = 3,
  NotificationTab selected = NotificationTab.all,
  ValueChanged<NotificationTab>? onTab,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotificationHeroHeader(
          unreadCount: unread,
          markingAll: false,
          selected: selected,
          onTabChanged: onTab ?? (_) {},
          onBack: () {},
          onMarkAllRead: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('brand notif → OfficialBrandAvatar (bukan teks NL)',
      (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'b1', 'title': 'Feed kamu sudah tayang', 'body': 'disetujui',
      'type': 'feed', 'eventType': 'feed_published',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.text('NL'), findsNothing);
    expect(find.byType(OfficialBrandAvatar), findsOneWidget);
  });

  testWidgets('like agregat (actorAvatarUrls ≥2) → avatar bertumpuk',
      (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'agg1', 'title': '3 orang menyukai Feed kamu', 'body': '',
      'type': 'feed', 'eventType': 'feed_new_like',
      'actorAvatarUrls': ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('notification-stacked-avatars')),
        findsOneWidget);
  });

  testWidgets('header: judul, counter "N baru", Tandai dibaca, 4 pill',
      (tester) async {
    await _pumpHeader(tester);
    expect(find.text('Notifikasi'), findsOneWidget);
    expect(find.text('3 baru'), findsOneWidget);
    expect(find.text('Tandai dibaca'), findsOneWidget);
    for (final label in ['Semua', 'Aktivitas', 'Transaksi', 'Promo']) {
      expect(find.text(label), findsOneWidget);
    }
    // Subtitle lama hilang.
    expect(
        find.textContaining('Update pesanan, promo'), findsNothing);
  });

  testWidgets('counter sembunyi saat unread 0; tap pill memanggil callback',
      (tester) async {
    NotificationTab? tapped;
    await _pumpHeader(tester, unread: 0, onTab: (t) => tapped = t);
    expect(find.textContaining('baru'), findsNothing);
    await tester.tap(find.text('Transaksi'));
    expect(tapped, NotificationTab.transaction);
  });

  testWidgets('tidak ada bobot font > w600 di header', (tester) async {
    await _pumpHeader(tester);
    final texts = tester.widgetList<Text>(find.byType(Text));
    for (final t in texts) {
      final w = t.style?.fontWeight;
      expect(w == null || w.index <= FontWeight.w600.index, isTrue,
          reason: 'teks "${t.data}" memakai $w');
    }
  });

  group('NotificationRow', () {
    testWidgets('satu timestamp relatif; tanpa tanggal absolut/chevron/pill',
        (tester) async {
      await _pumpRow(tester, _notif());
      expect(find.text('2 jam'), findsOneWidget);
      expect(find.textContaining('Juli'), findsNothing,
          reason: 'datetime absolut dihapus');
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.text('Feed'), findsNothing,
          reason: 'pill teks kategori dihapus');
    });

    testWidgets('unread menampilkan bar aksen; read tidak', (tester) async {
      await _pumpRow(tester, _notif(read: false));
      expect(
          find.byKey(const ValueKey('notification-unread-bar')), findsOneWidget);
      await _pumpRow(tester, _notif(read: true));
      expect(
          find.byKey(const ValueKey('notification-unread-bar')), findsNothing);
    });

    testWidgets('thumbnail hanya render saat imageUrl ada', (tester) async {
      await _pumpRow(tester, _notif());
      expect(find.byKey(const ValueKey('notification-thumb')), findsNothing);
      await _pumpRow(
          tester, _notif(imageUrl: 'https://example.com/x.jpg'));
      expect(find.byKey(const ValueKey('notification-thumb')), findsOneWidget);
    });

    testWidgets('CTA tonal tampil untuk notif actionable', (tester) async {
      await _pumpRow(
          tester,
          _notif(
              title: 'Voucher spesial buat kamu',
              body: 'Pakai sebelum hangus',
              category: 'voucher'));
      expect(find.text('Pakai Voucher'), findsOneWidget);
    });
  });

  group('NotificationRow follow avatar', () {
    AppNotification followNotif() => AppNotification.fromApiJson({
          'id': 'f1',
          'title': 'Andi mulai mengikuti kamu',
          'body': '',
          'type': 'info',
          'eventType': 'user_followed',
          'imageUrl': 'https://cdn/andi.jpg',
          'createdAt':
              DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
          'read': false,
        });

    testWidgets('follow → avatar aktor di KIRI, thumbnail kanan disembunyikan',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(notification: followNotif(), onTap: () {}),
        ),
      ));
      expect(find.byKey(const ValueKey('notification-actor-avatar')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('notification-thumb')), findsNothing,
          reason: 'foto follower tampil di kiri, bukan slot thumbnail kanan');
    });
  });

  testWidgets('actorAvatarUrl → avatar aktor di kiri (mis. komentar)',
      (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'c1', 'title': 'Andi mengomentari postinganmu', 'body': 'keren!',
      'type': 'info', 'eventType': 'feed_new_comment',
      'actorAvatarUrl': 'https://cdn/andi.jpg',
      'thumbnailUrl': 'https://cdn/post.jpg',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('notification-actor-avatar')),
        findsOneWidget);
    // Komentar tetap punya thumbnail POST di kanan (beda dari follow).
    expect(find.byKey(const ValueKey('notification-thumb')), findsOneWidget);
  });

  testWidgets(
      'follow pasca-P2 (actorAvatarUrl) → avatar kiri, tanpa thumbnail kanan',
      (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'f2', 'title': 'Budi mulai mengikuti kamu', 'body': '',
      'type': 'info', 'eventType': 'user_followed',
      'actorAvatarUrl': 'https://cdn/budi.jpg',
      'thumbnailUrl': 'https://cdn/budi.jpg',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('notification-actor-avatar')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('notification-thumb')), findsNothing,
        reason: 'follow tak punya konten post → tak ada thumbnail kanan');
  });

  testWidgets(
      'non-follow ber-actorAvatarUrl tanpa thumbnail → avatar kiri saja',
      (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'l1', 'title': 'Andi menyukai postinganmu', 'body': '',
      'type': 'info', 'eventType': 'feed_new_like',
      'actorAvatarUrl': 'https://cdn/andi.jpg',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('notification-actor-avatar')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('notification-thumb')), findsNothing);
  });

  testWidgets('voucher gratis ongkir → ikon truk di avatar kiri', (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'vf1', 'title': '🚚 Gratis Ongkir dari Natalo!', 'body': 'Klaim sekarang',
      'type': 'promo', 'eventType': 'voucher_freeship_published',
      'url': '/member/vouchers',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
  });

  testWidgets('voucher diskon → ikon sell/tag di avatar kiri', (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'vd1', 'title': '🎟️ Voucher diskon baru', 'body': 'Diskon 20% pakai HEMAT20',
      'type': 'promo', 'eventType': 'voucher_discount_published',
      'url': '/member/vouchers',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byIcon(Icons.sell_rounded), findsOneWidget);
  });

  group('ikon kategori baru', () {
    testWidgets('balasan ulasan → ikon rate_review (keluarga ungu mention)',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'rr1', 'title': 'Toko membalas ulasanmu', 'body': 'Terima kasih!',
        'type': 'review', 'eventType': 'review_reply',
        'url': '/products/produk-a', 'createdAt': DateTime.now().toIso8601String(),
        'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.rate_review_rounded), findsOneWidget);
    });

    testWidgets('pengingat tukar poin → ikon gift, bukan tiket promo',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lr1', 'title': 'Poin kamu siap ditukar',
        'body': '1.250 poin bisa jadi voucher belanja.',
        'type': 'loyalty', 'eventType': 'loyalty_redeem_reminder',
        'url': '/member/loyalty', 'createdAt': DateTime.now().toIso8601String(),
        'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
      expect(find.byIcon(Icons.confirmation_number_rounded), findsNothing);
    });

    testWidgets('flash sale → ikon petir, bukan tiket voucher biasa',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'fs1', 'title': 'Flash Sale sudah dimulai',
        'body': 'Diskon s/d 50% terbatas.',
        'type': 'promo', 'url': '/products?flashSale=1',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });

    testWidgets('feed like tanpa foto aktor → badge ikon hati, bukan play-circle',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'fl1', 'title': 'Andi menyukai postinganmu', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
    });

    testWidgets('feed comment tanpa foto aktor → badge ikon chat bubble',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'fc1', 'title': 'Andi mengomentari postinganmu', 'body': 'keren!',
        'type': 'feed', 'eventType': 'feed_new_comment',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });

    testWidgets('feed share tanpa foto aktor → badge ikon share', (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'fsh1', 'title': 'Postinganmu dibagikan', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_share',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
    });

    testWidgets('postingan disetujui → ikon centang, bukan play-circle',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'fap1', 'title': 'Postinganmu sudah disetujui', 'body': '',
        'type': 'feed', 'eventType': 'feed_post_approved',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
    });

    testWidgets('postingan ditolak → ikon silang merah, bukan play-circle',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'frj1', 'title': 'Postinganmu belum bisa ditayangkan',
        'body': 'Cek alasannya.', 'type': 'feed',
        'eventType': 'feed_post_rejected',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
    });

    testWidgets('postingan menunggu review → ikon jam pasir abu netral',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'fpend1', 'title': 'Feed kamu sedang menunggu review',
        'body': '', 'type': 'feed', 'eventType': 'feed_review_pending',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
    });
  });

  group('lencana like', () {
    testWidgets('like berfoto → lencana ❤️ di sudut avatar', (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk1', 'title': 'Andi menyukai postinganmu', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'actorAvatarUrl': 'https://cdn/andi.jpg',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsOneWidget);
    });

    testWidgets('like agregat (stacked) → lencana ❤️ di atas tumpukan',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk2', 'title': '3 orang menyukai Feed kamu', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'actorAvatarUrls': ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-stacked-avatars')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsOneWidget);
    });

    testWidgets('like TANPA foto → tak ada lencana baru (cabang brand tak disentuh)',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk3', 'title': 'Feed kamu mendapat like baru', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsNothing);
    });

    testWidgets('komentar berfoto → TIDAK dapat lencana like', (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk4', 'title': 'Andi berkomentar', 'body': 'keren!',
        'type': 'feed', 'eventType': 'feed_new_comment',
        'actorAvatarUrl': 'https://cdn/andi.jpg',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsNothing);
    });
  });

  group('avatar netral user biasa tanpa foto (bugfix vs logo brand)', () {
    testWidgets('komentar user biasa TANPA foto → avatar inisial netral, bukan logo brand',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'na1', 'title': 'Andi berkomentar', 'body': 'keren!',
        'type': 'feed', 'eventType': 'feed_new_comment',
        'actorName': 'Andi',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byType(ProfileAvatar), findsOneWidget);
      expect(find.byType(OfficialBrandAvatar), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('komentar akun official TANPA foto → tetap logo brand (tak berubah)',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'na2', 'title': 'Natalo Petshop Official berkomentar',
        'body': 'terima kasih!', 'type': 'feed', 'eventType': 'feed_new_comment',
        'actorName': 'Natalo Petshop Official',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byType(OfficialBrandAvatar), findsOneWidget);
      expect(find.byType(ProfileAvatar), findsNothing);
    });

    testWidgets('notif sistem tanpa aktor (mis. Feed kamu sudah tayang) → tetap logo brand',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'na3', 'title': 'Feed kamu sudah tayang', 'body': 'disetujui',
        'type': 'feed', 'eventType': 'feed_published',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byType(OfficialBrandAvatar), findsOneWidget);
      expect(find.byType(ProfileAvatar), findsNothing);
    });
  });
}
