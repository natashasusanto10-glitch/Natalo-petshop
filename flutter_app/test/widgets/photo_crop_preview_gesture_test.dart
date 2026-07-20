import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/photo_crop/photo_crop_preview.dart';
import 'package:natalo_petshop_flutter/widgets/photo_crop/photo_crop_transform.dart';

void main() {
  testWidgets(
      'drag on preview pans the photo and does NOT scroll the ancestor list',
      (tester) async {
    final transform = PhotoCropTransform();
    addTearDown(transform.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    // Portrait preloaded size → cover di frame 300×300 memberi ruang pan
    // VERTIKAL (±75px). Vertikal = sumbu yang justru diperebutkan ListView,
    // jadi ini menguji EagerGestureRecognizer benar-benar memblok scroll.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              Center(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: PhotoCropPreview(
                    file: File('layout_only.jpg'),
                    fitOriginal: false,
                    cropTransform: transform,
                    preloadedImageSize: const Size(400, 600),
                  ),
                ),
              ),
              const SizedBox(height: 1400, child: ColoredBox(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(transform.offsetFraction, Offset.zero);
    expect(scroll.offset, 0);

    final center = tester.getCenter(find.byType(PhotoCropPreview));
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(0, -40)); // seret ke atas
    await tester.pump();

    // Foto ikut ke atas (offsetFraction.dy negatif ≈ -40/300), dan ListView
    // TIDAK scroll — bukti Eager memenangkan arena, bukan scroll.
    expect(transform.offsetFraction.dy, lessThan(-0.05));
    expect(scroll.offset, 0);

    await g.up();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Pan dalam batas → tetap tersimpan (tak snap balik ke nol), scroll tetap 0.
    expect(transform.offsetFraction.dy, lessThan(0));
    expect(scroll.offset, 0);
  });
}
