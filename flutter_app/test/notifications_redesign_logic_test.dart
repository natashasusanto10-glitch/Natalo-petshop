import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';
import 'package:natalo_petshop_flutter/screens/notifications_screen.dart';

AppNotification _n({
  String title = 'Judul',
  String body = '',
  String type = 'info',
  String? category,
  String? eventType,
}) =>
    AppNotification.fromApiJson({
      'id': 'x',
      'title': title,
      'body': body,
      'type': type,
      if (category != null) 'category': category,
      if (eventType != null) 'eventType': eventType,
      'createdAt': '2026-07-19T00:00:00.000Z',
      'read': false,
    });

void main() {
  group('NotificationTab.matches', () {
    test('activity mencakup mention, feed, dan pengumuman lama', () {
      expect(
          NotificationTab.activity
              .matches(_n(eventType: 'feed_mention', title: 'menyebut kamu')),
          isTrue);
      expect(
          NotificationTab.activity
              .matches(_n(title: 'Feed kamu sudah tayang', category: 'feed')),
          isTrue);
      expect(
          NotificationTab.activity
              .matches(_n(type: 'announcement', title: 'Pengumuman toko')),
          isTrue);
    });

    test('transaction = pesanan; promo = promo; tidak tumpang tindih', () {
      final order = _n(title: 'Pesanan dikirim', category: 'order');
      final promo = _n(title: 'Flash sale diskon 40%', category: 'promo');
      expect(NotificationTab.transaction.matches(order), isTrue);
      expect(NotificationTab.promo.matches(order), isFalse);
      expect(NotificationTab.promo.matches(promo), isTrue);
      expect(NotificationTab.activity.matches(promo), isFalse);
    });

    test('all memuat semuanya', () {
      expect(NotificationTab.all.matches(_n()), isTrue);
    });

    test('label 4 tab benar', () {
      expect(NotificationTab.values.map((t) => t.label).toList(),
          ['Semua', 'Aktivitas', 'Transaksi', 'Promo']);
    });
  });

  group('notificationTimeBucket', () {
    final now = DateTime(2026, 7, 19, 10, 30); // Minggu pagi

    test('hari kalender sama = today (termasuk 00:00)', () {
      expect(notificationTimeBucket(now, DateTime(2026, 7, 19, 0, 0)),
          NotificationTimeBucket.today);
      expect(notificationTimeBucket(now, DateTime(2026, 7, 19, 10, 29)),
          NotificationTimeBucket.today);
    });

    test('kemarin (hari kalender -1) = yesterday walau <24 jam', () {
      expect(notificationTimeBucket(now, DateTime(2026, 7, 18, 23, 59)),
          NotificationTimeBucket.yesterday);
      expect(notificationTimeBucket(now, DateTime(2026, 7, 18, 0, 0)),
          NotificationTimeBucket.yesterday);
    });

    test('2-7 hari lalu = thisWeek; lebih = earlier', () {
      expect(notificationTimeBucket(now, DateTime(2026, 7, 17, 12, 0)),
          NotificationTimeBucket.thisWeek);
      expect(notificationTimeBucket(now, DateTime(2026, 7, 12, 12, 0)),
          NotificationTimeBucket.thisWeek);
      expect(notificationTimeBucket(now, DateTime(2026, 7, 11, 12, 0)),
          NotificationTimeBucket.earlier);
    });
  });

  group('shortRelativeTime', () {
    final now = DateTime(2026, 7, 19, 10, 30);
    test('format singkat tanpa kata "lalu"', () {
      expect(shortRelativeTime(now, now.subtract(const Duration(seconds: 30))),
          'baru saja');
      expect(shortRelativeTime(now, now.subtract(const Duration(minutes: 5))),
          '5 menit');
      expect(shortRelativeTime(now, now.subtract(const Duration(hours: 20))),
          '20 jam');
      expect(shortRelativeTime(now, now.subtract(const Duration(days: 3))),
          '3 hari');
      expect(shortRelativeTime(now, now.subtract(const Duration(days: 14))),
          '2 minggu');
      expect(shortRelativeTime(now, now.subtract(const Duration(days: 90))),
          '3 bulan');
      expect(shortRelativeTime(now, now.subtract(const Duration(days: 400))),
          '1 tahun');
    });
  });
}
