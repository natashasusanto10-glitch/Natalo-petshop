import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_collapsing_header.dart';

void main() {
  Widget harness({
    required double width,
    required double shrinkOffset,
    int initialIndex = 0,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(width, 844), padding: const EdgeInsets.only(top: 47)),
        child: DefaultTabController(
          length: 3,
          initialIndex: initialIndex,
          child: Builder(
            builder: (context) {
              final controller = DefaultTabController.of(context);
              final delegate = PublicProfileCollapsingHeaderDelegate(
                controller: controller,
                title: 'mona.pet',
                expandedHeader: const SizedBox(
                  key: Key('expanded_profile'),
                  height: 220,
                  child: Text('Profil lengkap'),
                ),
                onBack: () {},
                onOverflow: () {},
              );
              return Scaffold(
                body: SizedBox(
                  width: width,
                  height: delegate.maxExtent,
                  child: delegate.build(context, shrinkOffset, false),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('expanded, intermediate, and collapsed states stay overflow-free',
      (tester) async {
    for (final width in <double>[393, 360]) {
      for (final progress in <double>[0, 0.5, 1]) {
        await tester.pumpWidget(harness(
          width: width,
          shrinkOffset:
              PublicProfileCollapsingHeaderDelegate.collapseRange * progress,
        ));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('tab group moves smoothly from right to left', (tester) async {
    Future<Rect> rectAt(double offset) async {
      await tester.pumpWidget(harness(width: 393, shrinkOffset: offset));
      return tester.getRect(find.byKey(const Key('public_profile_tab_group')));
    }

    final expanded = await rectAt(0);
    final middle =
        await rectAt(PublicProfileCollapsingHeaderDelegate.collapseRange / 2);
    final collapsed =
        await rectAt(PublicProfileCollapsingHeaderDelegate.collapseRange);

    expect(middle.width, lessThan(expanded.width));
    expect(collapsed.width, lessThan(middle.width));
    expect(middle.right, lessThan(expanded.right));
    expect(collapsed.right, lessThan(middle.right));
  });

  testWidgets('keeps selected tab and exposes compact navigation semantics',
      (tester) async {
    await tester.pumpWidget(harness(
      width: 393,
      shrinkOffset: PublicProfileCollapsingHeaderDelegate.collapseRange,
      initialIndex: 1,
    ));

    expect(find.bySemanticsLabel('Kembali'), findsOneWidget);
    expect(find.bySemanticsLabel('Opsi lainnya'), findsOneWidget);
    expect(find.text('mona.pet'), findsOneWidget);
    final selected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(selected.properties.selected, isTrue);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('reverse scroll resolves the same geometry', (tester) async {
    await tester.pumpWidget(harness(
      width: 393,
      shrinkOffset: PublicProfileCollapsingHeaderDelegate.collapseRange,
    ));
    await tester.pumpWidget(harness(
      width: 393,
      shrinkOffset: PublicProfileCollapsingHeaderDelegate.collapseRange / 2,
    ));
    final reverse =
        tester.getRect(find.byKey(const Key('public_profile_tab_group')));

    await tester.pumpWidget(harness(
      width: 393,
      shrinkOffset: PublicProfileCollapsingHeaderDelegate.collapseRange / 2,
    ));
    expect(
      tester.getRect(find.byKey(const Key('public_profile_tab_group'))),
      reverse,
    );
  });

  testWidgets('real regular header caps long bio and keeps actions visible',
      (tester) async {
    const profile = PublicProfile(
      id: 'profile-1',
      name: 'Mona dengan nama profil yang cukup panjang',
      username: 'mona.pet',
      bio: 'Baris pertama bio yang panjang dan informatif.\n'
          'Baris kedua berisi cerita hewan peliharaan.\n'
          'Baris ketiga masih berlanjut.\n'
          'Baris keempat tidak boleh mendorong tombol keluar layar.\n'
          'Baris kelima juga harus dipotong dengan rapi.',
      postCount: 83,
      followersCount: 4378,
      followingCount: 4,
    );

    for (final width in <double>[393, 360]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              padding: const EdgeInsets.only(top: 47),
            ),
            child: DefaultTabController(
              length: 3,
              child: Builder(
                builder: (context) {
                  final delegate = PublicProfileCollapsingHeaderDelegate(
                    controller: DefaultTabController.of(context),
                    title: profile.displayHandle,
                    topPadding: 47,
                    expandedHeight: PublicProfileCollapsingHeaderDelegate
                        .regularExpandedHeight,
                    onBack: () {},
                    onOverflow: () {},
                    expandedHeader: const PublicProfileExpandedHeader(
                      profile: profile,
                      followBusy: false,
                      onFollowToggle: _noop,
                      onShareProfile: _noop,
                    ),
                  );
                  return Scaffold(
                    body: SizedBox(
                      width: width,
                      height: delegate.maxExtent,
                      child: delegate.build(context, 0, false),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
          find.byKey(const Key('public_profile_action_row')), findsOneWidget);
      final bio = tester.widget<Text>(find.textContaining('Baris pertama'));
      expect(bio.maxLines, 3);
      expect(bio.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets('PublicProfileScreen scaffold never installs bottom navigation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PublicProfileScreen(username: 'mona.pet')),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _noop() {}
