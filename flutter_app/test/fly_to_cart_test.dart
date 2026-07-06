import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/fly_to_cart.dart';

void main() {
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
}
