// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/app_toast.dart';

Widget _host(void Function(BuildContext) onReady) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onReady(context));
            return const SizedBox.expand();
          },
        ),
      ),
    );

void main() {
  testWidgets('showBanner renders message + action and fires onAction',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host((context) {
      AppToast.showBanner(
        context,
        'Voucher berhasil ditukar!',
        subtitle: 'Cek di Voucher Member',
        kind: ToastKind.success,
        actionLabel: 'Lihat',
        onAction: () => tapped = true,
      );
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Voucher berhasil ditukar!'), findsOneWidget);
    expect(find.text('Cek di Voucher Member'), findsOneWidget);
    expect(find.text('Lihat'), findsOneWidget);

    await tester.tap(find.text('Lihat'));
    await tester.pump();
    expect(tapped, isTrue);

    // Let it auto-dismiss so the test's timers drain.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('showBanner auto-dismisses after duration', (tester) async {
    await tester.pumpWidget(_host((context) {
      AppToast.showBanner(context, 'Kode disalin',
          kind: ToastKind.success,
          duration: const Duration(milliseconds: 600));
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Kode disalin'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // duration
    await tester.pump(const Duration(milliseconds: 400)); // reverse anim
    await tester.pump(const Duration(milliseconds: 400)); // removal delay
    expect(find.text('Kode disalin'), findsNothing);
  });
}
