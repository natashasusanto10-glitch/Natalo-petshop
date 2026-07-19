import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';
import 'package:natalo_petshop_flutter/screens/notifications_screen.dart';

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
}
