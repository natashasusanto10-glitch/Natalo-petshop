import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:natalo_petshop_flutter/widgets/animated_shortcut_icon.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all eight assets load and render at key animation phases',
      (tester) async {
    final compositions = <LottieComposition>[];
    await tester.runAsync(() async {
      for (final icon in ShortcutArtwork.values) {
        final composition = await AssetLottie(icon.asset).load();
        expect(composition.duration.inMilliseconds, greaterThan(2000));
        expect(composition.warnings, isEmpty, reason: icon.name);
        expect(composition.images.values.every((i) => i.loadedImage != null),
            isTrue,
            reason: icon.name);
        compositions.add(composition);
      }
    });
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                for (final phase in [0.0, .35, .65, .9])
                  Row(children: [
                    for (final composition in compositions)
                      Expanded(
                        child: SizedBox(
                          height: 140,
                          child: Lottie(
                            composition: composition,
                            controller: AlwaysStoppedAnimation(phase),
                          ),
                        ),
                      ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    const output = String.fromEnvironment('SHORTCUT_CONTACT_SHEET');
    if (output.isNotEmpty) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('loops, pauses in background, and respects reduced motion',
      (tester) async {
    final oldInterval = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() =>
        VisibilityDetectorController.instance.updateInterval = oldInterval);
    await tester
        .runAsync(() => AssetLottie(ShortcutArtwork.voucher.asset).load());
    Future<void> mount({bool reduce = false}) => tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: const Center(
                child: AnimatedShortcutIcon(artwork: ShortcutArtwork.voucher)),
          ),
        ));
    await mount();
    await tester.pump();
    final controller =
        tester.widget<LottieBuilder>(find.byType(LottieBuilder)).controller!;
    expect(controller.isAnimating, isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(controller.isAnimating, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.isAnimating, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.isAnimating, isTrue);
    await mount(reduce: true);
    await tester.pump();
    expect(controller.isAnimating, isFalse);
    expect(controller.value, ShortcutArtwork.voucher.stillProgress);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
