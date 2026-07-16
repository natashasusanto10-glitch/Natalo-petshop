import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';

void main() {
  testWidgets('expanded chrome does not install an inactive blur layer',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollFraction: 0,
      isOfficial: true,
    ));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const Key('public_profile_glass_layer')), findsNothing);
  });

  testWidgets('glass phase installs exactly one active blur layer',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollFraction: .8,
      isOfficial: true,
    ));

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const Key('public_profile_glass_layer')), findsOneWidget);
  });

  testWidgets('collapsed chrome uses one blur layer above underlapping grid',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollFraction: 1,
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
        scrollFraction: fraction,
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
      scrollFraction: .5,
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
      scrollFraction: 1,
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
          scrollFraction: fraction,
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
      scrollFraction: 1,
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
      scrollFraction: 1,
      isOfficial: false,
      onGridTap: () => gridTaps++,
    ));

    await tester.tapAt(const Offset(196, 300));
    expect(gridTaps, 1);
  });

  for (final width in <double>[360, 393]) {
    for (final scale in <double>[1.3, 2]) {
      testWidgets(
          'official identity metrics fit mandatory actions at $width and $scale',
          (tester) async {
        await tester.pumpWidget(identityMetricsHarness(
          width: width,
          textScale: scale,
          profile: const PublicProfile(
            id: 'official-1',
            name: 'Natalo Petshop Official',
            username: 'natalopetshop',
            isOfficial: true,
          ),
        ));

        expect(find.text('Ikuti'), findsOneWidget);
        expect(find.text('Pesan'), findsOneWidget);
        expect(find.byTooltip('Bagikan Profil'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'regular long bio metrics fit three lines at $width and $scale',
          (tester) async {
        await tester.pumpWidget(identityMetricsHarness(
          width: width,
          textScale: scale,
          profile: const PublicProfile(
            id: 'profile-1',
            name: 'Nama Pengguna Dengan Teks Panjang',
            username: 'pengguna.panjang',
            bio:
                'Baris pertama bio panjang. Baris kedua menjelaskan profil. Baris ketiga tetap terlihat tanpa terpotong.',
          ),
        ));

        expect(find.text('Ikuti'), findsOneWidget);
        expect(find.byTooltip('Bagikan Profil'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('official base metrics fit mandatory identity at normal scale',
      (tester) async {
    await tester.pumpWidget(identityMetricsHarness(
      width: 393,
      textScale: 1,
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        username: 'natalopetshop',
        isOfficial: true,
      ),
    ));

    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Pesan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'official brand bio and mutuals fit iPhone 15 Pro at normal scale',
      (tester) async {
    await tester.pumpWidget(identityMetricsHarness(
      width: 393,
      textScale: 1,
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        username: 'natalopetshop',
        bio: 'Akun resmi Natalo Petshop & Aquarium 🐾',
        isOfficial: true,
        mutualFollowers: PublicProfileMutualSummary(
          items: [
            PublicProfileMutualFollower(
              id: 'mutual-1',
              name: 'Rani Anabul Medan',
              username: 'rani.anabul',
            ),
          ],
          totalCount: 24,
        ),
      ),
    ));

    expect(
        find.text('Akun resmi Natalo Petshop & Aquarium 🐾'), findsOneWidget);
    expect(find.textContaining('Diikuti oleh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scaler in <TextScaler>[
    const TextScaler.linear(3.2),
    const _NonlinearAccessibilityScaler(),
  ]) {
    testWidgets('identity caps extreme visual scaling without hiding actions',
        (tester) async {
      await tester.pumpWidget(identityMetricsHarness(
        width: 320,
        textScaler: scaler,
        profile: const PublicProfile(
          id: 'official-1',
          name: 'Natalo Petshop Official Dengan Nama Sangat Panjang',
          username: 'natalopetshop',
          bio: 'Bio akun resmi tetap terbaca dan tidak mendorong aksi keluar.',
          isOfficial: true,
        ),
      ));

      expect(find.text('Ikuti'), findsOneWidget);
      expect(find.text('Pesan'), findsOneWidget);
      expect(find.byTooltip('Bagikan Profil'), findsOneWidget);
      expect(find.bySemanticsLabel('Ikuti'), findsOneWidget);
      expect(find.bySemanticsLabel('Pesan'), findsOneWidget);
      expect(find.bySemanticsLabel('Bagikan Profil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget identityMetricsHarness({
  required double width,
  double? textScale,
  TextScaler? textScaler,
  required PublicProfile profile,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        textScaler: textScaler ?? TextScaler.linear(textScale!),
      ),
      child: Builder(builder: (context) {
        final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: metrics.identityHeight,
              child: PublicProfileExpandedHeader(
                profile: profile,
                followBusy: false,
                chatEnabled: true,
                onFollowToggle: () {},
                onShareProfile: () {},
                onMessage: () {},
              ),
            ),
          ),
        );
      }),
    ),
  );
}

class _NonlinearAccessibilityScaler extends TextScaler {
  const _NonlinearAccessibilityScaler();

  @override
  double scale(double fontSize) {
    if (fontSize < 10) return fontSize * 1.1;
    return fontSize < 14 ? fontSize * 3.4 : fontSize * 2.6;
  }

  @override
  double get textScaleFactor => 3;
}

Widget overlayHarness({
  required double width,
  required double scrollFraction,
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
          final scrollOffset = metrics.scrollSpaceHeight * scrollFraction;
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
