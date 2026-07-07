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
    // Drain kerja async gate (ensureAuthReady timeout 3s + settleDelay 900ms).
    // User tidak login di test → popup tidak muncul; cukup pastikan tidak crash.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
