import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';

void main() {
  testWidgets('expanded chrome does not install any inactive blur layer',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      t: 0,
      isOfficial: true,
    ));

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('glass phase installs floating per-chip blur layers',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      t: .8,
      isOfficial: true,
    ));

    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('collapsed chrome floats glass chips above underlapping grid',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      t: 1,
      isOfficial: true,
    ));

    expect(find.byType(BackdropFilter), findsWidgets);
    expect(
        find.byKey(const Key('public_profile_grid_underlay')), findsOneWidget);
  });

  testWidgets('reduced motion removes blur but retains readable tint',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 360,
      t: 1,
      isOfficial: false,
      disableAnimations: true,
    ));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      find.byKey(const Key('liquid_glass_reduced_motion')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 360, 393, 430]) {
    testWidgets('toolbar fits at width $width', (tester) async {
      for (final t in <double>[0, .25, .5, .75, 1]) {
        await tester.pumpWidget(overlayHarness(
          width: width,
          t: t,
          isOfficial: false,
        ));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('only real chrome controls intercept the grid', (tester) async {
    var gridTaps = 0;
    await tester.pumpWidget(overlayHarness(
      width: 393,
      t: 1,
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
  required double t,
  required bool isOfficial,
  bool disableAnimations = false,
  VoidCallback? onGridTap,
}) {
  final profile = PublicProfile(
    id: isOfficial ? 'official-1' : 'profile-1',
    name: isOfficial ? 'Natalo Petshop Official' : 'Mona',
    username: isOfficial ? 'natalopetshop' : 'mona.pet',
    isOfficial: isOfficial,
  );
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        padding: const EdgeInsets.only(top: 47),
        disableAnimations: disableAnimations,
      ),
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
                PublicProfileChromeOverlay(
                  profile: profile,
                  t: t,
                  metrics: metrics,
                  onBack: () {},
                  onShareProfile: () {},
                  onOverflow: isOfficial ? null : () {},
                ),
              ],
            ),
          ),
        );
      }),
    ),
  );
}
