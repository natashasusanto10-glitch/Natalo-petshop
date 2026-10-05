import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  testWidgets('wishlist vector animation renders its complete cycle',
      (tester) async {
    final composition = await AssetLottie(
      'assets/lottie/wishlist-pets-cards-v1.json',
    ).load();
    expect(composition.duration, const Duration(seconds: 6));
    final key = GlobalKey();
    const export = bool.fromEnvironment('EXPORT_WISHLIST');
    for (var frame = 0; frame < 180; frame += 6) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
          key: key,
          child: SizedBox(
              width: 640,
              height: 460,
              child: Lottie(
                composition: composition,
                animate: false,
                controller: AlwaysStoppedAnimation(frame / 180),
              )),
        )),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'frame $frame');
      if (export) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('../output/wishlist-motion/frames');
          await directory.create(recursive: true);
          await File(
                  '${directory.path}/${frame.toString().padLeft(3, '0')}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
