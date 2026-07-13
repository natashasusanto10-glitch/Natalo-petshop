import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/single_dispose_guard.dart';

class _DelayedLocalWrapper {
  final initialized = Completer<void>();
  int disposeCount = 0;

  Future<void> initialize() => initialized.future;

  Future<void> dispose() async {
    disposeCount++;
  }
}

void main() {
  test('in-flight eviction and init failure dispose the resource once',
      () async {
    final guard = SingleDisposeGuard<Object>();
    final resource = Object();
    final gate = Completer<void>();
    var disposeCount = 0;

    final eviction = guard.dispose(resource, () async {
      disposeCount++;
      await gate.future;
    });
    final initFailure = guard.dispose(resource, () async => disposeCount++);
    gate.complete();
    await Future.wait([eviction, initFailure]);

    expect(disposeCount, 1);
  });

  test('local MP4 delayed init and unmount dispose wrapper exactly once',
      () async {
    final guard = SingleDisposeGuard<_DelayedLocalWrapper>();
    final wrapper = _DelayedLocalWrapper();

    final init = wrapper.initialize().catchError((_) async {
      await guard.dispose(wrapper, wrapper.dispose);
    });
    await guard.dispose(wrapper, wrapper.dispose); // Widget unmount.
    wrapper.initialized.completeError(StateError('disposed during init'));
    await init;

    expect(wrapper.disposeCount, 1);
  });
}
