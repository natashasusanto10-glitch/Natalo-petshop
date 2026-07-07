import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/launch_popup_campaign.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_dialog.dart';

const _promo = LaunchPopupCampaign(
  id: 'p1', tone: LaunchPopupTone.promo, imageUrl: null,
  title: 'Diskon 30% khusus member',
  body: 'Hemat 30% untuk vitamin dan makanan.',
  categoryLabel: 'Promo', ctaLabel: 'Lihat produk',
  ctaHref: '/produk/abc', dismissLabel: 'Nanti saja',
);

const _infoOnly = LaunchPopupCampaign(
  id: 'a1', tone: LaunchPopupTone.announcement, imageUrl: null,
  title: 'Libur Idul Adha', body: 'Toko tutup 6-7 Juli.',
  categoryLabel: 'Pengumuman', dismissLabel: 'Mengerti',
);

/// Membuka dialog dan mengembalikan Future outcome-nya. Semua langkah
/// pembukaan (pump widget, tap tombol 'open', drain frame) sudah selesai
/// (di-`await`) sebelum fungsi ini return, sehingga caller aman melakukan
/// interaksi lain (mis. tap CTA/dismiss) segera setelahnya tanpa race
/// dengan `TestAsyncUtils.guard`. Future outcome yang dikembalikan baru
/// akan selesai setelah user menutup dialog.
Future<Future<LaunchPromoOutcome>> _open(
    WidgetTester tester, LaunchPopupCampaign c) async {
  final completer = Completer<LaunchPromoOutcome>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async =>
                completer.complete(await showLaunchPromoDialog(context, campaign: c)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  return completer.future;
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('menampilkan judul, body, dan kedua tombol', (tester) async {
    await _open(tester, _promo);
    expect(find.text('Diskon 30% khusus member'), findsOneWidget);
    expect(find.text('Hemat 30% untuk vitamin dan makanan.'), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-popup-cta')), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-popup-dismiss')), findsOneWidget);
  });

  testWidgets('tap CTA mengembalikan outcome cta', (tester) async {
    final outcome = await _open(tester, _promo);
    await tester.tap(find.byKey(const ValueKey('launch-popup-cta')));
    await _drain(tester);
    expect(await outcome, LaunchPromoOutcome.cta);
  });

  testWidgets('tap dismiss mengembalikan outcome dismiss', (tester) async {
    final outcome = await _open(tester, _promo);
    await tester.tap(find.byKey(const ValueKey('launch-popup-dismiss')));
    await _drain(tester);
    expect(await outcome, LaunchPromoOutcome.dismiss);
  });

  testWidgets('mode info: tombol CTA disembunyikan', (tester) async {
    await _open(tester, _infoOnly);
    expect(find.byKey(const ValueKey('launch-popup-cta')), findsNothing);
    expect(find.byKey(const ValueKey('launch-popup-dismiss')), findsOneWidget);
    expect(find.text('Mengerti'), findsOneWidget);
  });
}
