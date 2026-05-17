// Smoke test sederhana — pastikan app bisa mount tanpa crash. Test sebenarnya
// di-port dari Capacitor saat masing-masing screen dibikin real.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const NataloPetshopApp());
    // Tunggu first frame settle.
    await tester.pump();
    // App harus mount tanpa exception — kalau sampai sini lulus.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
