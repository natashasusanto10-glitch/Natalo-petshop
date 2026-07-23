import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_router.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';

void main() {
  group('DeepLinkService public share lifecycle', () {
    test('keeps a cold-start link pending until navigation is ready', () async {
      final dispatcher = _FakeDispatcher();
      final service = DeepLinkService.test(dispatcher: dispatcher);

      service
          .handleExternalUri('https://www.natalopetshop.com/feed/post-1?v=a');
      await pumpEventQueue();
      expect(dispatcher.targets, isEmpty);

      dispatcher.isReady = true;
      await service.onNavigatorReady();

      expect(dispatcher.targets, const [FeedPostDeepLink('post-1')]);
    });

    test('deduplicates initial and stream delivery by normalized target',
        () async {
      final dispatcher = _FakeDispatcher()..isReady = true;
      var now = DateTime(2026, 7, 23, 9);
      final service = DeepLinkService.test(
        dispatcher: dispatcher,
        now: () => now,
      );

      service.handleExternalUri('https://natalopetshop.com/u/Natalo?v=one');
      await pumpEventQueue();
      service.handleExternalUri(
        'https://www.natalopetshop.com/u/natalo?v=two&utm_source=wa',
      );
      await pumpEventQueue();

      expect(dispatcher.targets, const [ProfileDeepLink('natalo')]);

      now = now.add(const Duration(seconds: 3));
      service
          .handleExternalUri('https://www.natalopetshop.com/u/natalo?v=three');
      await pumpEventQueue();
      expect(dispatcher.targets, const [
        ProfileDeepLink('natalo'),
        ProfileDeepLink('natalo'),
      ]);
    });

    test(
        'keeps different links distinct while only the newest pending target remains',
        () async {
      final dispatcher = _FakeDispatcher();
      final service = DeepLinkService.test(dispatcher: dispatcher);

      service
          .handleExternalUri('https://www.natalopetshop.com/feed/old-post?v=1');
      service.handleExternalUri(
          'https://www.natalopetshop.com/products/new-product?v=1');
      await pumpEventQueue();

      dispatcher.isReady = true;
      await service.onNavigatorReady();
      expect(dispatcher.targets, const [ProductDeepLink('new-product')]);

      service.handleExternalUri(
          'https://www.natalopetshop.com/feed/next-post?v=1');
      await pumpEventQueue();
      expect(dispatcher.targets, const [
        ProductDeepLink('new-product'),
        FeedPostDeepLink('next-post'),
      ]);
    });

    test('ignores invalid public URLs without dispatching a fallback route',
        () async {
      final dispatcher = _FakeDispatcher()..isReady = true;
      final service = DeepLinkService.test(dispatcher: dispatcher);

      service.handleExternalUri(
          'https://www.natalopetshop.com.evil.test/feed/post-1');
      service.handleExternalUri('http://www.natalopetshop.com/feed/post-1');
      service
          .handleExternalUri('https://www.natalopetshop.com/feed/post-1/extra');
      service.handleExternalUri('mailto:test@natalopetshop.com');
      await pumpEventQueue();

      expect(dispatcher.targets, isEmpty);
    });
  });
}

class _FakeDispatcher implements DeepLinkTargetDispatcher {
  bool isReady = false;
  final List<NataloDeepLinkTarget> targets = <NataloDeepLinkTarget>[];

  @override
  Future<void> dispatch(NataloDeepLinkTarget target) async {
    targets.add(target);
  }
}
