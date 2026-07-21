import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_hero.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_viewer_route.dart';

void main() {
  testWidgets('postHeroTag ter-scope dan unik per permukaan', (tester) async {
    expect(postHeroTag('profile', 'p1'), 'post-hero/profile/p1');
    expect(postHeroTag('saved', 'p1'), isNot(postHeroTag('profile', 'p1')));
  });

  testWidgets('PostHero memasang Hero dengan transitionOnUserGestures true',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PostHero(
          scope: 'profile',
          postId: 'p1',
          child: SizedBox(width: 10, height: 10)),
    ));
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'post-hero/profile/p1');
    expect(hero.transitionOnUserGestures, isTrue);
    expect(hero.flightShuttleBuilder, isNotNull);
  });

  testWidgets(
      'push PostViewerRoute menerbangkan hero tile ke slot (shuttle hadir mid-flight)',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: PostHero(
              scope: 'profile',
              postId: 'p1',
              child: SizedBox(
                  width: 40,
                  height: 40,
                  child: ColoredBox(
                      color: Colors.blue, key: const Key('tile-media')))),
        ),
      ),
    ));
    navKey.currentState!.push(PostViewerRoute<void>(
        builder: (_) => const Scaffold(
              body: Center(
                  child: PostHero(
                      scope: 'profile',
                      postId: 'p1',
                      child: SizedBox(
                          width: 300,
                          height: 300,
                          child: ColoredBox(color: Colors.blue)))),
            )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140)); // mid-flight

    // Hero flight = widget media digambar di overlay. Ambil SEMUA ColoredBox
    // yang hidup saat itu (tile asal, shuttle overlay, tujuan) dan pastikan
    // ada satu dengan ukuran interpolasi ketat antara 40 dan 300.
    final sizes = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((box) {
          try {
            final element = find
                .byWidgetPredicate((w) => identical(w, box))
                .evaluate()
                .first;
            return (element as Element).size;
          } catch (_) {
            return null;
          }
        })
        .whereType<Size>()
        .toList();

    expect(sizes, isNotEmpty);
    final hasInterpolated = sizes.any((s) => s.width > 40 && s.width < 300);
    expect(hasInterpolated, isTrue,
        reason:
            'Diharapkan ada widget dengan ukuran interpolasi mid-flight antara 40 dan 300, dapat: $sizes');

    await tester.pump(const Duration(milliseconds: 400)); // selesai
  });

  testWidgets('pop tanpa pasangan tag → fade tanpa error (mode gagal jinak)',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()), // grid TANPA hero
    ));
    navKey.currentState!.push(PostViewerRoute<void>(
        builder: (_) => const Scaffold(
              body: PostHero(
                  scope: 'profile',
                  postId: 'nope',
                  child: SizedBox(width: 300, height: 300)),
            )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
