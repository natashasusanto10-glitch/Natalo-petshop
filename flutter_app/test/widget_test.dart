// Smoke test — pastikan app mount tanpa crash walau LaunchPromoGate aktif.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    // Gate membaca SharedPreferences (onboarding) — sediakan mock kosong.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NataloPetshopApp());
    // Drain kerja async gate: worst case ensureAuthReady timeout 3s +
    // settleDelay 2s = 5s (memberStore tidak pernah initialized di test ini).
    // Pump 6s (120 x 50ms) supaya ada margin di atas 5s worst case.
    // User tidak login di test → popup tidak muncul; cukup pastikan tidak crash.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
