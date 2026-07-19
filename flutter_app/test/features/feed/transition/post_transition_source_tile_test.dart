import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_transition_source_tile.dart';

void main() {
  test('tile identity includes both source scope and post ID', () {
    const allA = PostTransitionTileId(scope: 'all', postId: 'a');
    const sameAllA = PostTransitionTileId(scope: 'all', postId: 'a');

    expect(allA, sameAllA);
    expect(allA.hashCode, sameAllA.hashCode);
    expect(
      allA,
      isNot(const PostTransitionTileId(scope: 'photos', postId: 'a')),
    );
    expect(allA, isNot(const PostTransitionTileId(scope: 'all', postId: 'b')));
  });

  testWidgets(
    'registry returns root-overlay geometry and placeholder immediately',
    (tester) async {
      final registry = PostTransitionTileRegistry();
      const id = PostTransitionTileId(scope: 'all', postId: 'a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 11, top: 17),
                child: SizedBox(
                  width: 120,
                  height: 160,
                  child: PostTransitionSourceTile(
                    registry: registry,
                    id: id,
                    fallbackColor: Colors.blueGrey,
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final target = registry.resolve(id);
      expect(target, isNotNull);
      expect(target!.rect, const Rect.fromLTWH(11, 17, 120, 160));
      expect(target.viewportSize, const Size(800, 600));
      expect(target.proxy.imageInfo, isNull);
      expect(target.proxy.placeholderColor, Colors.blueGrey);
      expect(target.layoutGeneration, 0);
      target.proxy.dispose();
    },
  );

  testWidgets('snapshots retain the layout generation used for geometry', (
    tester,
  ) async {
    final registry = PostTransitionTileRegistry();
    const id = PostTransitionTileId(scope: 'all', postId: 'generation');
    await tester.pumpWidget(_tileHost(registry, id));

    final first = registry.resolve(id)!;
    registry.markLayoutChanged();
    final second = registry.resolve(id)!;

    expect(first.layoutGeneration, 0);
    expect(second.layoutGeneration, 1);
    expect(registry.layoutGeneration, 1);
    first.proxy.dispose();
    second.proxy.dispose();
  });

  testWidgets('suppression is reversible and unregister restores ownership', (
    tester,
  ) async {
    final registry = PostTransitionTileRegistry();
    const id = PostTransitionTileId(scope: 'all', postId: 'b');
    await tester.pumpWidget(_tileHost(registry, id));

    registry.setSuppressed(id, true);
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('post-transition-tile-opacity-b')),
          )
          .opacity,
      0,
    );

    registry.setSuppressed(id, false);
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('post-transition-tile-opacity-b')),
          )
          .opacity,
      1,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(registry.resolve(id), isNull);
  });

  testWidgets('resolved proxy owns a retained frame after tile disposal', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    picture.dispose();
    final provider = _ImmediateImageProvider(image);
    final registry = PostTransitionTileRegistry();
    const id = PostTransitionTileId(scope: 'all', postId: 'frame');

    await tester.pumpWidget(_tileHost(registry, id, imageProvider: provider));
    await tester.pump();

    final target = registry.resolve(id)!;
    expect(target.proxy.imageInfo, isNotNull);
    expect(provider.obtainKeyCalls, 1);
    registry.resolve(id)!.proxy.dispose();
    expect(
      provider.obtainKeyCalls,
      1,
      reason: 'resolve must not resolve media',
    );

    final handlesWithTileAndProxy = target.proxy.imageInfo!.image
        .debugGetOpenHandleStackTraces()!
        .length;
    await tester.pumpWidget(const SizedBox.shrink());
    final handlesAfterTileDisposal = target.proxy.imageInfo!.image
        .debugGetOpenHandleStackTraces()!
        .length;

    expect(handlesAfterTileDisposal, handlesWithTileAndProxy - 1);
    expect(target.proxy.imageInfo!.image.width, 1);

    target.proxy.dispose();
    expect(
      image.debugGetOpenHandleStackTraces()!.length,
      handlesAfterTileDisposal - 1,
    );
    await provider.evict();
    image.dispose();
  });
}

Widget _tileHost(
  PostTransitionTileRegistry registry,
  PostTransitionTileId id, {
  ImageProvider<Object>? imageProvider,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 120,
        height: 160,
        child: PostTransitionSourceTile(
          registry: registry,
          id: id,
          fallbackColor: Colors.blueGrey,
          imageProvider: imageProvider,
          child: const ColoredBox(color: Colors.red),
        ),
      ),
    ),
  );
}

class _ImmediateImageProvider extends ImageProvider<_ImmediateImageProvider> {
  _ImmediateImageProvider(this.image);

  final ui.Image image;
  int obtainKeyCalls = 0;

  @override
  Future<_ImmediateImageProvider> obtainKey(ImageConfiguration configuration) {
    obtainKeyCalls++;
    return SynchronousFuture<_ImmediateImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ImmediateImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}
