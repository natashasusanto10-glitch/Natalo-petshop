# Notifikasi Premium Inset-Grouped Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign halaman Notifikasi lonceng ke gaya premium inset-grouped (mockup #2): header hero + 4 tab pill, grup waktu, kartu island, baris identitas/kalimat/thumbnail, unread bar, CTA tonal.

**Architecture:** Semua perubahan visual di `lib/screens/notifications_screen.dart` (file tunggal, pola existing dipertahankan). Logika baru yang perlu unit-test (bucketing waktu, pemetaan 4 tab, waktu relatif singkat) dibuat sebagai fungsi/enum murni `@visibleForTesting` di file yang sama. Model `AppNotification` dapat field `imageUrl` opsional. Perilaku non-visual (fetch, mark-read, `_navigateForNotification`, pull-refresh) TIDAK disentuh.

**Tech Stack:** Flutter, Dart, `flutter_test`.

## Global Constraints

- Token WAJIB: `NataloColors.primary` (#1E5FBF), `NataloColors.primarySoft` (#EEF4FF), `NataloColors.heroTop`, `NataloColors.heroGradientV`, `NataloColors.onHeroBright`. Tidak ada warna hex karangan baru KECUALI yang sudah ada di file (warna kategori `_NotificationVisual`, gray `#EEF1F5` yang dipakai halaman gray lain).
- Bobot font HANYA `FontWeight.w400` dan `FontWeight.w600`. Semua `w700`/`w900` di elemen yang diredesign dihapus.
- Font default theme (PlusJakartaSans) — jangan set fontFamily manual.
- Kontrak hero-blue status bar (AnnotatedRegion + strip `ColoredBox(heroTop)`) di `_buildAuthenticatedContent` SUDAH benar — jangan diubah.
- `_navigateForNotification`, `_openNotification`, `_load`, `_markAllRead`, `notificationService.*` TIDAK berubah.
- Setiap task: `flutter analyze` bersih pada file yang disentuh + test hijau → commit.
- Branch kerja: `claude/notifications-premium-redesign` (worktree `C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/flutter-feed-ui-design-f74eb8`). Semua path di bawah relatif ke root worktree; jalankan perintah dari `flutter_app/`.

---

### Task 1: Model — field `imageUrl` opsional

**Files:**
- Modify: `flutter_app/lib/models/app_notification.dart`
- Test: `flutter_app/test/models/app_notification_image_url_test.dart` (baru)

**Interfaces:**
- Produces: `AppNotification.imageUrl` (`String?`), ter-parse dari `imageUrl` | `image_url` | `thumbnailUrl`, ikut di `copyWith` (tidak berubah saat copy).

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/models/app_notification_image_url_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';

void main() {
  Map<String, dynamic> base() => {
        'id': 'n1',
        'title': 'Judul',
        'body': 'Isi',
        'type': 'info',
        'createdAt': '2026-07-19T00:00:00.000Z',
        'read': false,
      };

  test('parses imageUrl from camelCase key', () {
    final n = AppNotification.fromApiJson(
        {...base(), 'imageUrl': 'https://cdn/img.jpg'});
    expect(n.imageUrl, 'https://cdn/img.jpg');
  });

  test('parses imageUrl from snake_case and thumbnailUrl fallbacks', () {
    expect(
      AppNotification.fromApiJson(
              {...base(), 'image_url': 'https://cdn/a.jpg'})
          .imageUrl,
      'https://cdn/a.jpg',
    );
    expect(
      AppNotification.fromApiJson(
              {...base(), 'thumbnailUrl': 'https://cdn/b.jpg'})
          .imageUrl,
      'https://cdn/b.jpg',
    );
  });

  test('null when absent, and survives copyWith', () {
    final n = AppNotification.fromApiJson(base());
    expect(n.imageUrl, isNull);
    final withImg = AppNotification.fromApiJson(
        {...base(), 'imageUrl': 'https://cdn/img.jpg'});
    expect(withImg.copyWith(read: true).imageUrl, 'https://cdn/img.jpg');
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL (compile error: imageUrl tidak ada)**

Run: `cd flutter_app && flutter test test/models/app_notification_image_url_test.dart`
Expected: FAIL — `The getter 'imageUrl' isn't defined for the class 'AppNotification'`.

- [ ] **Step 3: Tambah field + parsing + copyWith**

Di `lib/models/app_notification.dart`:

1. Tambah field setelah `infoNote` (baris ~17): `final String? imageUrl;`
2. Tambah param konstruktor setelah `this.infoNote,`: `this.imageUrl,`
3. Di `fromApiJson`, setelah parsing `infoNote`:

```dart
      imageUrl: (json['imageUrl'] ?? json['image_url'] ?? json['thumbnailUrl'])
          ?.toString(),
```

4. Di `copyWith`, tambahkan `imageUrl: imageUrl,` pada objek yang dikembalikan (field tidak ikut parameter — hanya diteruskan).

- [ ] **Step 4: Jalankan test, pastikan LULUS + analyze**

Run: `cd flutter_app && flutter test test/models/app_notification_image_url_test.dart && flutter analyze lib/models/app_notification.dart`
Expected: PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/app_notification.dart flutter_app/test/models/app_notification_image_url_test.dart
git commit -m "feat(notifikasi): field imageUrl opsional di AppNotification"
```

---

### Task 2: Logika murni — bucket waktu, 4 tab, waktu relatif singkat

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (tambah enum/fungsi `@visibleForTesting` di level top file, dekat `_notificationHaystack`)
- Test: `flutter_app/test/notifications_redesign_logic_test.dart` (baru)

**Interfaces:**
- Consumes: `_NotificationFilter` (enum privat existing dengan `.matches`), `_isMentionNotification`, `_isAnnouncementNotification` (fungsi privat existing di file yang sama).
- Produces (dipakai Task 3-4):
  - `enum NotificationTab { all, activity, transaction, promo }` dengan `String get label` ("Semua"/"Aktivitas"/"Transaksi"/"Promo") dan `bool matches(AppNotification item)`.
  - `enum NotificationTimeBucket { today, yesterday, thisWeek, earlier }` dengan `String get label` ("HARI INI"/"KEMARIN"/"MINGGU INI"/"SEBELUMNYA").
  - `NotificationTimeBucket notificationTimeBucket(DateTime now, DateTime createdAt)`.
  - `String shortRelativeTime(DateTime now, DateTime past)` → "baru saja"/"5 menit"/"20 jam"/"3 hari"/"2 minggu"/"4 bulan"/"1 tahun".

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/notifications_redesign_logic_test.dart`:

```dart
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
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL (symbol tidak ada)**

Run: `cd flutter_app && flutter test test/notifications_redesign_logic_test.dart`
Expected: FAIL — `Undefined name 'NotificationTab'` dst.

- [ ] **Step 3: Implementasi enum + fungsi**

Di `lib/screens/notifications_screen.dart`, tambahkan SETELAH definisi `_notificationHaystack` (level top file):

```dart
/// 4 tab redesign (Semua/Aktivitas/Transaksi/Promo). Aktivitas = gabungan
/// filter lama Disebut + Feed + Pengumuman; Transaksi = Pesanan lama; Promo
/// tetap. Publik + @visibleForTesting supaya pemetaan bisa diuji unit.
@visibleForTesting
enum NotificationTab {
  all('Semua'),
  activity('Aktivitas'),
  transaction('Transaksi'),
  promo('Promo');

  final String label;
  const NotificationTab(this.label);

  bool matches(AppNotification item) {
    return switch (this) {
      NotificationTab.all => true,
      NotificationTab.activity => _isMentionNotification(item) ||
          _NotificationFilter.feed.matches(item) ||
          _isAnnouncementNotification(item),
      NotificationTab.transaction => _NotificationFilter.order.matches(item),
      NotificationTab.promo => _NotificationFilter.promo.matches(item),
    };
  }
}

/// Bucket waktu untuk header grup daftar notifikasi (berbasis HARI KALENDER
/// lokal, bukan selisih 24 jam — "kemarin 23:59" tetap KEMARIN walau baru
/// 31 menit berlalu).
@visibleForTesting
enum NotificationTimeBucket {
  today('HARI INI'),
  yesterday('KEMARIN'),
  thisWeek('MINGGU INI'),
  earlier('SEBELUMNYA');

  final String label;
  const NotificationTimeBucket(this.label);
}

@visibleForTesting
NotificationTimeBucket notificationTimeBucket(
    DateTime now, DateTime createdAt) {
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final dayDiff = today.difference(thatDay).inDays;
  if (dayDiff <= 0) return NotificationTimeBucket.today;
  if (dayDiff == 1) return NotificationTimeBucket.yesterday;
  if (dayDiff <= 7) return NotificationTimeBucket.thisWeek;
  return NotificationTimeBucket.earlier;
}

/// Waktu relatif SINGKAT ("20 jam", "3 hari") — satu-satunya timestamp baris
/// redesign. Beda dari formatRelativeTime (formatters.dart) yang berakhiran
/// "lalu"; di daftar padat, akhiran itu berulang & memanjangkan baris.
@visibleForTesting
String shortRelativeTime(DateTime now, DateTime past) {
  final diff = now.difference(past);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit';
  if (diff.inHours < 24) return '${diff.inHours} jam';
  if (diff.inDays < 7) return '${diff.inDays} hari';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} minggu';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} bulan';
  return '${(diff.inDays / 365).floor()} tahun';
}
```

Catatan: enum publik boleh berada di file screen — pola `reviewNotificationFallbackRoute @visibleForTesting` sudah ada di file ini.

- [ ] **Step 4: Jalankan test, pastikan LULUS + analyze**

Run: `cd flutter_app && flutter test test/notifications_redesign_logic_test.dart && flutter analyze lib/screens/notifications_screen.dart`
Expected: PASS; `No issues found!` (warning `unused_element` belum muncul karena enum publik).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_logic_test.dart
git commit -m "feat(notifikasi): logika 4 tab + bucket waktu + waktu relatif singkat"
```

---

### Task 3: Header hero baru + tab pill di dalam header

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart`:
  - `_NotificationsScreenState`: ganti `_NotificationFilter _filter` → `NotificationTab _tab`.
  - `_NotificationHeader` (baris ~571-666): rombak.
  - `_NotificationTabs` (baris ~667-737): HAPUS (digantikan pill di header).
  - `_buildAuthenticatedContent`: sambungkan.
- Test: `flutter_app/test/notifications_redesign_widget_test.dart` (baru)

**Interfaces:**
- Consumes: `NotificationTab` (Task 2), `NataloColors.heroGradientV/heroTop/onHeroBright`, `AppHaptics.selection`.
- Produces: `_NotificationHeader` dengan signature baru:

```dart
_NotificationHeader({
  required int unreadCount,
  required bool markingAll,
  required NotificationTab selected,
  required ValueChanged<NotificationTab> onTabChanged,
  required VoidCallback onBack,
  required VoidCallback onMarkAllRead,
})
```

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/notifications_redesign_widget_test.dart`. Widget test menyuntik hasil via `notificationService`? TIDAK — service adalah singleton network. Pola paling ringan: test header sebagai widget terisolasi. Karena `_NotificationHeader` privat, uji lewat permukaan publik: pump `NotificationsScreen` butuh login+network → berat. Solusinya: jadikan header PUBLIK ringan `NotificationHeroHeader` (tanpa underscore) supaya bisa diuji langsung — masih di file yang sama.

```dart
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
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart`
Expected: FAIL — `NotificationHeroHeader` tidak terdefinisi.

- [ ] **Step 3: Implementasi header baru + hapus tabs lama**

Di `lib/screens/notifications_screen.dart`:

**(a)** GANTI seluruh `class _NotificationHeader` (baris ~571-666) dengan:

```dart
/// Header hero redesign: judul + counter "N baru" + "Tandai dibaca" + 4 tab
/// pill DI DALAM area gradient biru (menggantikan _NotificationTabs strip
/// putih). Publik + dipakai langsung oleh widget test.
@visibleForTesting
class NotificationHeroHeader extends StatelessWidget {
  final int unreadCount;
  final bool markingAll;
  final NotificationTab selected;
  final ValueChanged<NotificationTab> onTabChanged;
  final VoidCallback onBack;
  final VoidCallback onMarkAllRead;

  const NotificationHeroHeader({
    super.key,
    required this.unreadCount,
    required this.markingAll,
    required this.selected,
    required this.onTabChanged,
    required this.onBack,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: NataloColors.heroGradientV,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
              ),
              const Text(
                'Notifikasi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.1,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+ baru' : '$unreadCount baru',
                    style: const TextStyle(
                      color: NataloColors.onHeroBright,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed:
                    unreadCount == 0 || markingAll ? null : onMarkAllRead,
                style: TextButton.styleFrom(
                  foregroundColor: NataloColors.onHeroBright,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: markingAll
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white70),
                      )
                    : const Text(
                        'Tandai dibaca',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w400),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: NotificationTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = NotificationTab.values[index];
                final active = tab == selected;
                return InkWell(
                  onTap: () => onTabChanged(tab),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tab.label,
                      style: TextStyle(
                        color: active
                            ? NataloColors.heroTop
                            : const Color(0xFFC9D8EE),
                        fontSize: 12.5,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

Catatan warna: `#C9D8EE` = teks pill non-aktif dari mockup yang disetujui; masih keluarga `onHeroBright` (#EAF1FC) — bila review menganggap ini "warna karangan", ganti ke `NataloColors.onHeroBright` dengan alpha 0.8.

**(b)** HAPUS seluruh `class _NotificationTabs` (baris ~667-737 lama).

**(c)** Di `_NotificationsScreenState`:
- Ganti field: `NotificationTab _tab = NotificationTab.all;` (hapus `_NotificationFilter _filter`).
- Di `_visibleItems`: ganti `items.where(_filter.matches)` → `items.where(_tab.matches)`.
- Di `_navigateForNotification` baris ~274 ada pemakaian `_NotificationFilter.feed.matches(item)` — BIARKAN (enum lama tetap ada untuk logika matching; hanya UI tab yang berganti).
- Di `_buildAuthenticatedContent`, ganti blok `_NotificationHeader(...)` + `_NotificationTabs(...)` menjadi:

```dart
                  NotificationHeroHeader(
                    unreadCount: unread,
                    markingAll: _markingAll,
                    selected: _tab,
                    onTabChanged: (tab) {
                      AppHaptics.selection();
                      setState(() {
                        _tab = tab;
                        _cachedVisibleItems = null; // invalidate — tab berubah
                      });
                    },
                    onBack: () => Navigator.maybePop(context),
                    onMarkAllRead: _markAllRead,
                  ),
```

- `_NotificationEmptyState(filter: _filter)` → ubah param menjadi `tab: _tab` dan sesuaikan kelasnya: field `final NotificationTab tab;` — teks empty state per tab: gunakan `tab.label` pada template yang ada (mis. "Belum ada notifikasi ${tab == NotificationTab.all ? '' : tab.label}"). Pertahankan struktur visual empty state yang ada, hanya ganti sumber label. Ikon per tab: `switch (tab) { all => Icons.notifications_none_rounded, activity => Icons.play_circle_outline_rounded, transaction => Icons.receipt_long_rounded, promo => Icons.confirmation_number_rounded }`.

- [ ] **Step 4: Jalankan test, pastikan LULUS + analyze**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart test/notifications_redesign_logic_test.dart test/notification_review_route_test.dart && flutter analyze lib/screens/notifications_screen.dart`
Expected: PASS semua; `No issues found!`. Jika `_NotificationFilter` memicu `unused_element` untuk value yang tak terpakai (mention/announcement dipakai via fungsi, all/order/promo/feed dipakai) — bila ada warning value tak terpakai, tambahkan `// ignore: unused_element` TIDAK diperbolehkan; solusi benar: value enum masih dipakai `matches` internal switch, jadi aman. Verifikasi analyze output.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notifikasi): header hero + 4 tab pill menggantikan strip tab putih"
```

---

### Task 4: Daftar — grup waktu + kartu island + baris redesign

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart`:
  - `_buildContent` (baris ~513-570): bangun struktur grup.
  - `_NotificationTile` (baris ~738-897): GANTI dengan `NotificationRow` publik.
- Test: `flutter_app/test/notifications_redesign_widget_test.dart` (tambah group)

**Interfaces:**
- Consumes: `NotificationTimeBucket`, `notificationTimeBucket`, `shortRelativeTime` (Task 2), `AppNotification.imageUrl` (Task 1), `_NotificationVisual.from`, `_notificationCtaLabel`, `_isMentionNotification`, `_isAnnouncementNotification`, `_NotificationFilter.feed.matches`.
- Produces:

```dart
@visibleForTesting
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required AppNotification notification,
    required VoidCallback onTap,
  });
}
```

- [ ] **Step 1: Tambah widget test yang gagal**

Tambahkan di `test/notifications_redesign_widget_test.dart` (import tambahan `package:natalo_petshop_flutter/models/app_notification.dart`):

```dart
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

// Tambahkan group berikut di main():
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
```

Catatan: test thumbnail hanya memeriksa KEBERADAAN widget ber-key (bukan load network image); implementasi wajib memakai `Image.network` di dalam container ber-key dengan `errorBuilder` supaya test tidak menyentuh network nyata — atau gunakan `CachedNetworkImage` pola file lain bila sudah diimpor di screen lain; pilih `Image.network` + `errorBuilder: (_, __, ___) => const SizedBox.shrink()` untuk tanpa dependensi baru.

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart`
Expected: FAIL — `NotificationRow` tidak terdefinisi.

- [ ] **Step 3: Implementasi `NotificationRow` + grup island di `_buildContent`**

**(a)** GANTI seluruh `class _NotificationTile` dengan:

```dart
/// Baris notifikasi redesign: identitas kiri → kalimat+waktu tengah →
/// thumbnail kanan (opsional). Unread = bar aksen kiri. Publik untuk test.
@visibleForTesting
class NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
  });

  bool get _isBrandIdentity =>
      _NotificationFilter.feed.matches(notification) ||
      _isAnnouncementNotification(notification);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visual = _NotificationVisual.from(notification);
    final ctaLabel = _notificationCtaLabel(notification);
    final imageUrl = notification.imageUrl;

    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          if (!notification.read)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                key: const ValueKey('notification-unread-bar'),
                width: 3,
                decoration: const BoxDecoration(
                  color: NataloColors.primary,
                  borderRadius:
                      BorderRadius.horizontal(right: Radius.circular(3)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _IdentityAvatar(
                  visual: visual,
                  brandIdentity: _isBrandIdentity,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: notification.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (notification.body.trim().isNotEmpty)
                              TextSpan(text: ' — ${notification.body.trim()}'),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (ctaLabel != null) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: NataloColors.primarySoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  ctaLabel,
                                  style: const TextStyle(
                                    color: NataloColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            shortRelativeTime(
                                DateTime.now(), notification.createdAt),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (imageUrl != null && imageUrl.trim().isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(
                    key: const ValueKey('notification-thumb'),
                    height: 46,
                    width: 46,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surfaceContainerHighest,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lingkaran identitas kiri: brand "NL" untuk notifikasi feed/pengumuman
/// (identitas Natalo), tint kategori + ikon untuk lainnya. Badge kategori
/// mini hanya saat identitas brand (kategori tetap terbaca).
class _IdentityAvatar extends StatelessWidget {
  final _NotificationVisual visual;
  final bool brandIdentity;

  const _IdentityAvatar({required this.visual, required this.brandIdentity});

  @override
  Widget build(BuildContext context) {
    final core = brandIdentity
        ? Container(
            height: 42,
            width: 42,
            decoration: const BoxDecoration(
              color: NataloColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text(
              'NL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(visual.icon, color: visual.color, size: 20),
          );

    if (!brandIdentity) return core;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            height: 17,
            width: 17,
            decoration: BoxDecoration(
              color: visual.color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).colorScheme.surface, width: 2),
            ),
            child: Icon(visual.icon, color: Colors.white, size: 9),
          ),
        ),
      ],
    );
  }
}
```

**(b)** Di `_buildContent`, GANTI blok `return NataloPawRefreshIndicator(... ListView.separated ...)` terakhir dengan struktur grup island:

```dart
    // Grup waktu → kartu island per grup (hairline antar baris).
    final now = DateTime.now();
    final groups = <NotificationTimeBucket, List<AppNotification>>{};
    for (final item in items) {
      groups
          .putIfAbsent(
              notificationTimeBucket(now, item.createdAt), () => [])
          .add(item);
    }
    final orderedBuckets = NotificationTimeBucket.values
        .where((b) => groups.containsKey(b))
        .toList();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        itemCount: orderedBuckets.length,
        itemBuilder: (context, groupIndex) {
          final bucket = orderedBuckets[groupIndex];
          final groupItems = groups[bucket]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
                child: Text(
                  bucket.label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < groupItems.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 68),
                          child: Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: isDark
                                ? cs.outlineVariant
                                : const Color(0xFFECF0F6),
                          ),
                        ),
                      NotificationRow(
                        notification: groupItems[i],
                        onTap: () => _openNotification(groupItems[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
```

Catatan: `AppAnimatedEntrance` per-item DIHAPUS (entrance per kartu-grup tidak diperlukan; menjaga daftar ringan). `#ECF0F6` = hairline dari mockup (satu-satunya hex baru selain `#C9D8EE`; keduanya dari mockup yang disetujui).

**(c)** Latar halaman: di `_buildAuthenticatedContent`, ganti `backgroundColor: Theme.of(context).scaffoldBackgroundColor` → 

```dart
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : const Color(0xFFEEF1F5),
```

(`#EEF1F5` = gray yang sama dengan halaman whole-page-gray lain, lihat `_homeGridSurfaceTint` di home_screen.dart.)

- [ ] **Step 4: Jalankan test, pastikan LULUS + analyze**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart test/notifications_redesign_logic_test.dart test/notification_review_route_test.dart test/notification_category_preferences_test.dart && flutter analyze lib/screens/notifications_screen.dart`
Expected: PASS semua; `No issues found!`. Bila `formatDateTime`/`AppStatusPill`/`AppAnimatedEntrance`/`formatRelativeTime` jadi import tak terpakai di file → hapus import/pemakaian sisa.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notifikasi): grup waktu + kartu island + baris identitas/kalimat/thumbnail"
```

---

### Task 5: Regresi penuh + sapu bersih

**Files:**
- Test: seluruh suite + analyze.

- [ ] **Step 1: Suite penuh notifikasi + analyze seluruh lib**

Run:
```bash
cd flutter_app && flutter test \
  test/models/app_notification_image_url_test.dart \
  test/notifications_redesign_logic_test.dart \
  test/notifications_redesign_widget_test.dart \
  test/notification_review_route_test.dart \
  test/notification_category_preferences_test.dart \
  && flutter analyze lib/screens/notifications_screen.dart lib/models/app_notification.dart
```
Expected: `All tests passed!`; `No issues found!`

- [ ] **Step 2: Cek sisa simbol mati**

Run: `cd flutter_app && grep -n "formatDateTime\|AppStatusPill\|AppAnimatedEntrance" lib/screens/notifications_screen.dart`
Expected: tidak ada hasil (semua pemakaian lama sudah dihapus). Bila masih ada di bagian yang TIDAK diredesign, biarkan (jangan refactor di luar scope).

- [ ] **Step 3: Commit penutup (bila ada penyesuaian)**

```bash
git add -A flutter_app && git commit -m "test(notifikasi): verifikasi regresi redesign premium" 
```
(Lewati bila working tree bersih.)

---

## Verifikasi manual (device — di luar test)

Setelah build: header/status-bar hero biru tetap menyatu (kontrak hero-blue); 4 pill nyaman di-scroll; kartu island + hairline terlihat premium; bar unread jelas; baris tanpa thumbnail rapi; tap baris tetap menavigasi benar (feed/pesanan/promo); mark-all-read jalan; pull-refresh daftar tetap ada; dark mode terbaca.
