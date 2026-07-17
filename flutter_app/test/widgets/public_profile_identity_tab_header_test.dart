import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_identity_tab_header.dart';

void main() {
  testWidgets(
      'tab group position is one exact linear function of t — never a '
      'second, independently-timed motion curve', (tester) async {
    const identityHeight = 271.0;
    const tabHeight = 52.0;
    const samples = <double>[0, 0.25, 0.5, 0.75, 1];
    final positions = <double, double>{};

    for (final t in samples) {
      await tester.pumpWidget(
        _harness(t: t, identityHeight: identityHeight, tabHeight: tabHeight),
      );
      positions[t] = tester
          .getTopLeft(find.byKey(const Key('public_profile_tab_group')))
          .dy;
    }

    // The tab bar's on-screen position is a natural, DIRECT consequence of
    // the identity area above it shrinking by `identityHeight * (1 - t)` —
    // the exact same `t` that drives every cosmetic field (opacity, blur).
    // There is no second, independently-timed position curve that could
    // drift out of sync with it (the historical bug this widget's own doc
    // comment describes: "a bare-icon flash bug (icon moved before its
    // background appeared)" caused by mixing two different curves).
    //
    // Note: the tab bar's absolute screen position is NOT expected to stay
    // constant — that would be geometrically impossible for a correct,
    // top-pinned, linearly-shrinking collapsing header (the space above the
    // tab must physically shrink for the sliver's scrollExtent contract to
    // hold). What matters, and what this asserts, is that position is a
    // single deterministic function of `t` alone.
    final baseline = positions[0]!;
    expect(baseline, identityHeight);
    for (final t in samples) {
      expect(
        positions[t],
        closeTo(baseline - identityHeight * t, 0.01),
        reason: 'unexpected tab position at t=$t — suggests a second, '
            'independently-timed motion curve has crept back in',
      );
    }
    // At full collapse the tab settles flush with the top of the header —
    // its documented "final position" reached purely as a consequence of
    // the identity area reaching zero height, not a separate animation.
    expect(positions[1], closeTo(0, 0.01));
  });

  testWidgets(
      'pill background is never zero once identity has started shrinking',
      (tester) async {
    for (final t in <double>[0.05, 0.1, 0.2, 0.3]) {
      await tester.pumpWidget(
        _harness(t: t, identityHeight: 271, tabHeight: 52),
      );
      // pillOpacity = _interval(t, 0, 0.55) — strictly > 0 for any t > 0, so
      // the active tab's pill background must already be partially visible
      // (never a hard 0-to-visible snap). Read the ACTUAL rendered pill
      // decoration rather than re-deriving the formula, so this fails if the
      // widget's real output ever stops matching it.
      final pillDecoration = tester
          .widget<DecoratedBox>(
            find.byKey(const Key('public_tab_posts_pill')),
          )
          .decoration as BoxDecoration;
      expect(pillDecoration.color, isNotNull);
      expect(pillDecoration.color!.a, greaterThan(0));
    }
  });
}

Widget _harness({
  required double t,
  required double identityHeight,
  required double tabHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: identityHeight + tabHeight,
        child: DefaultTabController(
          length: 3,
          child: Builder(builder: (context) {
            return PublicProfileIdentityTabHeader(
              profile: const PublicProfile(
                id: 'profile-1',
                name: 'Mona',
                username: 'mona.pet',
              ),
              followBusy: false,
              chatEnabled: true,
              tabController: DefaultTabController.of(context),
              identityHeight: identityHeight,
              tabHeight: tabHeight,
              t: t,
              onFollowToggle: () {},
            );
          }),
        ),
      ),
    ),
  );
}
