import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/launch_popup.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_dialog.dart';

const _withLink = LaunchPopup(
  id: 'p1',
  imageUrl: 'https://cdn.example.com/popup.png',
  imageAlt: 'Diskon 30% khusus member',
  href: '/products?diskon=1',
);

const _noLink = LaunchPopup(
  id: 'a1',
  imageUrl: 'https://cdn.example.com/info.png',
  imageAlt: 'Pengumuman',
);

/// Membuka dialog dan mengembalikan Future outcome-nya. Semua langkah
/// pembukaan (pump widget, tap tombol 'open', drain frame) sudah selesai
/// (di-`await`) sebelum fungsi ini return, sehingga caller aman melakukan
/// interaksi lain (mis. tap gambar/X) segera setelahnya tanpa race
/// dengan `TestAsyncUtils.guard`. Future outcome yang dikembalikan baru
/// akan selesai setelah user menutup dialog.
///
/// Catatan: CachedNetworkImage gagal load di test (network diblokir +
/// path_provider absen) → errorWidget SizedBox.shrink. GestureDetector +
/// tombol X tetap ada dan bisa di-tap — itu yang diuji di sini.
Future<Future<LaunchPromoOutcome>> _open(
    WidgetTester tester, LaunchPopup popup) async {
  final completer = Completer<LaunchPromoOutcome>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async => completer
                .complete(await showLaunchPromoDialog(context, popup: popup)),
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

  testWidgets('menampilkan area gambar dan tombol X', (tester) async {
    await _open(tester, _withLink);
    expect(find.byKey(const ValueKey('launch-popup-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-popup-close')), findsOneWidget);
  });

  testWidgets('tap gambar mengembalikan outcome cta saat ada href', (tester) async {
    final outcome = await _open(tester, _withLink);
    await tester.tap(find.byKey(const ValueKey('launch-popup-image')),
        warnIfMissed: false);
    await _drain(tester);
    expect(await outcome, LaunchPromoOutcome.cta);
  });

  testWidgets('tap X mengembalikan outcome dismiss', (tester) async {
    final outcome = await _open(tester, _withLink);
    await tester.tap(find.byKey(const ValueKey('launch-popup-close')));
    await _drain(tester);
    expect(await outcome, LaunchPromoOutcome.dismiss);
  });

  testWidgets('tanpa href: tap gambar tidak menutup dialog', (tester) async {
    await _open(tester, _noLink);
    await tester.tap(find.byKey(const ValueKey('launch-popup-image')),
        warnIfMissed: false);
    await _drain(tester);
    // Dialog masih terbuka — tombol X masih ada.
    expect(find.byKey(const ValueKey('launch-popup-close')), findsOneWidget);
  });
}
