import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/fade_route.dart';

/// Test regresi util fade-through route (dipakai 5 push flow posting —
/// lihat fase 2C-5). Cukup verifikasi push menampilkan halaman baru dan
/// pop kembali ke halaman asal, plus fullscreenDialog flag diteruskan.
void main() {
  testWidgets('fadeThroughRoute push menampilkan halaman baru, pop kembali',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  fadeThroughRoute(const Scaffold(body: Text('Halaman B'))),
                ),
                child: const Text('Buka'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Halaman B'), findsNothing);

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('Halaman B'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Halaman B'), findsNothing);
    expect(find.text('Buka'), findsOneWidget);
  });

  testWidgets('fadeThroughRoute meneruskan fullscreenDialog flag',
      (tester) async {
    final route = fadeThroughRoute<void>(
      const SizedBox.shrink(),
      fullscreenDialog: true,
    ) as PageRoute<void>;
    expect(route.fullscreenDialog, isTrue);

    final defaultRoute =
        fadeThroughRoute<void>(const SizedBox.shrink()) as PageRoute<void>;
    expect(defaultRoute.fullscreenDialog, isFalse);
  });
}
