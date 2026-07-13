import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/preload_generation.dart';

void main() {
  test('wrapper-only MP4 in-flight slot blocks a second manage pass', () {
    final controllers = <String, Object>{};
    final wrappers = <String, Object>{'post': Object()};
    expect(preloadSlotOccupied('post', controllers, wrappers), isTrue);
  });

  test('old failure cannot remove a newer wrapper/controller generation', () {
    final oldWrapper = Object();
    final oldController = Object();
    final newWrapper = Object();
    final newController = Object();
    final controllers = <String, Object>{'post': newController};
    final wrappers = <String, Object>{'post': newWrapper};

    expect(
      removeFailedPreloadGeneration(
        id: 'post',
        failedWrapper: oldWrapper,
        failedController: oldController,
        controllers: controllers,
        wrappers: wrappers,
      ),
      isFalse,
    );
    expect(wrappers['post'], same(newWrapper));
    expect(controllers['post'], same(newController));
  });
}
