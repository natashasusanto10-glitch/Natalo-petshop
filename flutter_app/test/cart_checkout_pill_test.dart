import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/cart_checkout_pill.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('render qty + total + hemat + arah panah', (tester) async {
    await tester.pumpWidget(_wrap(CartCheckoutPill(
      quantity: 3,
      totalText: 'Rp 312.000',
      savingText: 'Hemat Rp 41.000',
      voucherActive: true,
      onTap: () {},
    )));
    expect(find.text('3 item • Rp 312.000'), findsOneWidget);
    expect(find.text('Hemat Rp 41.000'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    // Voucher aktif → ikon tiket tampil.
    expect(
      find.byIcon(Icons.confirmation_number_rounded),
      findsOneWidget,
    );
  });

  testWidgets('tanpa saving & tanpa voucher → baris hemat + tiket hilang',
      (tester) async {
    await tester.pumpWidget(_wrap(CartCheckoutPill(
      quantity: 1,
      totalText: 'Rp 63.000',
      savingText: null,
      voucherActive: false,
      onTap: () {},
    )));
    expect(find.text('1 item • Rp 63.000'), findsOneWidget);
    expect(find.textContaining('Hemat'), findsNothing);
    expect(
      find.byIcon(Icons.confirmation_number_rounded),
      findsNothing,
    );
  });

  testWidgets('tap seluruh pil memanggil onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(CartCheckoutPill(
      quantity: 2,
      totalText: 'Rp 100.000',
      savingText: null,
      voucherActive: false,
      onTap: () => tapped++,
    )));
    await tester.tap(find.byType(CartCheckoutPill));
    expect(tapped, 1);
  });
}
