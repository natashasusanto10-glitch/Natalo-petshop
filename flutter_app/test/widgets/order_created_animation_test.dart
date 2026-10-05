import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:natalo_petshop_flutter/widgets/order_created_animation.dart';

void main() {
  testWidgets('plays once and retains final confirmation after rebuild',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OrderCreatedAnimation()));
    final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
    final composition = (await tester.runAsync(
        () => FileLottie(File('assets/lottie/order_created_pets.json')).load()))!;
    lottie.onLoaded!(composition);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    final controller = lottie.controller! as AnimationController;
    expect(controller.value, 1);
    expect(controller.isAnimating, isFalse);
    await tester.pumpWidget(const MaterialApp(home: OrderCreatedAnimation()));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.value, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion shows the final pose', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: OrderCreatedAnimation())));
    final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
    final composition = (await tester.runAsync(
        () => FileLottie(File('assets/lottie/order_created_pets.json')).load()))!;
    lottie.onLoaded!(composition);
    await tester.pump();
    expect(lottie.controller!.value, 1);
    expect((lottie.controller! as AnimationController).isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });
}
