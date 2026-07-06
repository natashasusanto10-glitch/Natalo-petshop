import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/fly_to_cart.dart';
import 'package:natalo_petshop_flutter/widgets/app_cart_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('flyImageToCart future complete di no-op path (tanpa cart icon)',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const Scaffold(body: SizedBox());
      }),
    ));

    // sourceKey tidak ter-attach + tidak ada AppCartButton di tree → path
    // no-op. Future harus tetap complete (tidak hang) supaya caller yang
    // await tidak menggantung.
    var completed = false;
    await flyImageToCart(
      context: ctx,
      imageUrl: 'https://example.com/x.jpg',
      sourceKey: GlobalKey(),
    ).then((_) => completed = true).timeout(const Duration(seconds: 2));

    expect(completed, isTrue);
  });

  testWidgets(
      'flyImageToCart future complete SETELAH animasi saat overlay & cart icon ada',
      (tester) async {
    final sourceKey = GlobalKey();
    late BuildContext ctx;

    // Tree lengkap: AppBar action punya AppCartButton (set
    // AppCartButton.activeIconKey saat build) + body punya sized box
    // dengan sourceKey. Builder capture context yang punya Overlay
    // ancestor (dari Navigator MaterialApp) supaya Overlay.maybeOf resolve.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: const [AppCartButton()],
        ),
        body: Builder(builder: (context) {
          ctx = context;
          return SizedBox(key: sourceKey, width: 40, height: 40);
        }),
      ),
    ));
    await tester.pump();

    // Precondition: cart icon ke-build → activeIconKey resolve.
    expect(AppCartButton.activeIconKey, isNotNull);
    expect(AppCartButton.activeIconKey!.currentContext, isNotNull);

    var completed = false;
    flyImageToCart(
      context: ctx,
      imageUrl: 'https://example.com/x.jpg',
      sourceKey: sourceKey,
    ).then((_) => completed = true);

    // Insert overlay + start animation. Future belum complete karena
    // animasi 900ms baru mulai.
    await tester.pump();
    expect(completed, isFalse);

    // Setelah durasi animasi penuh (900ms) → controller completed →
    // onComplete → completer.complete().
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });
}
