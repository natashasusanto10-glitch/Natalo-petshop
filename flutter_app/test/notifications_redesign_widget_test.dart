import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/notifications_screen.dart';

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
}
