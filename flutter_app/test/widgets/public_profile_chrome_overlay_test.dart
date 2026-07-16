import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';

void main() {
  testWidgets('collapsed chrome uses one blur layer above underlapping grid',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollOffset: 280,
      isOfficial: true,
    ));

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const Key('public_profile_glass_layer')), findsOneWidget);
    expect(
        find.byKey(const Key('public_profile_grid_underlay')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
    final tint = tester.widget<ColoredBox>(
      find.byKey(const Key('public_profile_glass_tint')),
    );
    expect(tint.color.a, lessThan(1));
  });

  testWidgets('right edge moves left monotonically and reverses exactly',
      (tester) async {
    final rights = <double>[];
    for (final fraction in <double>[0, .25, .5, .75, 1]) {
      await tester.pumpWidget(overlayHarness(
        width: 393,
        scrollOffset: 240 * fraction,
        isOfficial: false,
      ));
      rights.add(tester
          .getRect(find.byKey(const Key('public_profile_tab_group')))
          .right);
    }
    expect(rights[1], lessThanOrEqualTo(rights[0]));
    expect(rights[2], lessThanOrEqualTo(rights[1]));
    expect(rights[3], lessThanOrEqualTo(rights[2]));
    expect(rights[4], lessThanOrEqualTo(rights[3]));

    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollOffset: 120,
      isOfficial: false,
    ));
    expect(
      tester.getRect(find.byKey(const Key('public_profile_tab_group'))).right,
      rights[2],
    );
  });

  testWidgets('reduced motion removes blur but retains readable tint',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 360,
      scrollOffset: 240,
      isOfficial: false,
      disableAnimations: true,
    ));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      find.byKey(const Key('public_profile_reduced_motion_tint')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 360, 393, 430]) {
    testWidgets('all motion snapshots fit at width $width', (tester) async {
      for (final fraction in <double>[0, .25, .5, .75, 1]) {
        await tester.pumpWidget(overlayHarness(
          width: width,
          scrollOffset: 240 * fraction,
          isOfficial: false,
        ));
        final rect = tester.getRect(
          find.byKey(const Key('public_profile_tab_group')),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('dark chrome retains selected tab and forwards tab taps',
      (tester) async {
    var tapped = -1;
    await tester.pumpWidget(overlayHarness(
      width: 320,
      scrollOffset: 240,
      isOfficial: false,
      initialIndex: 1,
      themeMode: ThemeMode.dark,
      onTabTap: (index) => tapped = index,
    ));

    final selected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(selected.properties.selected, isTrue);
    await tester.tap(find.byTooltip('Belanja'));
    await tester.pumpAndSettle();
    expect(tapped, 2);
  });

  testWidgets('only real chrome controls intercept the grid', (tester) async {
    var gridTaps = 0;
    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollOffset: 240,
      isOfficial: false,
      onGridTap: () => gridTaps++,
    ));

    await tester.tapAt(const Offset(196, 300));
    expect(gridTaps, 1);
  });
}

Widget overlayHarness({
  required double width,
  required double scrollOffset,
  required bool isOfficial,
  bool disableAnimations = false,
  int initialIndex = 0,
  ThemeMode themeMode = ThemeMode.light,
  ValueChanged<int>? onTabTap,
  VoidCallback? onGridTap,
}) {
  final profile = PublicProfile(
    id: isOfficial ? 'official-1' : 'profile-1',
    name: isOfficial ? 'Natalo Petshop Official' : 'Mona',
    username: isOfficial ? 'natalopetshop' : 'mona.pet',
    isOfficial: isOfficial,
  );
  return MaterialApp(
    themeMode: themeMode,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        padding: const EdgeInsets.only(top: 47),
        disableAnimations: disableAnimations,
      ),
      child: DefaultTabController(
        length: 3,
        initialIndex: initialIndex,
        child: Builder(builder: (context) {
          final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
          return Scaffold(
            body: SizedBox(
              width: width,
              height: 852,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('public_profile_grid_underlay'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onGridTap,
                    ),
                  ),
                  Positioned.fill(
                    child: PublicProfileChromeOverlay(
                      profile: profile,
                      controller: DefaultTabController.of(context),
                      scrollOffset: scrollOffset,
                      metrics: metrics,
                      onBack: () {},
                      onShareProfile: () {},
                      onOverflow: isOfficial ? null : () {},
                      onTabTap: onTabTap,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    ),
  );
}
