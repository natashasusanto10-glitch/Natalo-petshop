import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/theme/app_theme.dart';
import 'package:natalo_petshop_flutter/widgets/profile_grid_geometry.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_content_tab_bar.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_header_motion.dart';
import 'package:visibility_detector/visibility_detector.dart';

const _logicalSize = Size(393, 852);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final textFontLoader = FontLoader('PlusJakartaSans')
      ..addFont(
        rootBundle.load('assets/fonts/PlusJakartaSans[wght].ttf'),
      );
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([
      textFontLoader.load(),
      iconFontLoader.load(),
    ]);
  });

  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() {
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 500);
  });

  testWidgets('official expanded iPhone 15 Pro', (tester) async {
    await _pumpGolden(tester, isOfficial: true, collapsed: false);
    await expectLater(
      find.byKey(const Key('official_expanded_golden')),
      matchesGoldenFile('public_profile_official_expanded.png'),
    );
  });

  testWidgets('official collapsed iPhone 15 Pro', (tester) async {
    await _pumpGolden(tester, isOfficial: true, collapsed: true);
    await expectLater(
      find.byKey(const Key('official_collapsed_golden')),
      matchesGoldenFile('public_profile_official_collapsed.png'),
    );
  });

  testWidgets('regular expanded iPhone 15 Pro', (tester) async {
    await _pumpGolden(tester, isOfficial: false, collapsed: false);
    await expectLater(
      find.byKey(const Key('regular_expanded_golden')),
      matchesGoldenFile('public_profile_regular_expanded.png'),
    );
  });

  testWidgets('regular collapsed iPhone 15 Pro', (tester) async {
    await _pumpGolden(tester, isOfficial: false, collapsed: true);
    await expectLater(
      find.byKey(const Key('regular_collapsed_golden')),
      matchesGoldenFile('public_profile_regular_collapsed.png'),
    );
  });

  testWidgets('production screen collapsed glass underlaps the real grid',
      (tester) async {
    await _pumpProductionCollapsedGolden(tester);

    final overlay = tester.widget<PublicProfileChromeOverlay>(
      find.byType(PublicProfileChromeOverlay),
    );
    final nestedScrollables = find.descendant(
      of: find.byType(NestedScrollView),
      matching: find.byType(Scrollable),
    );
    final outerPosition =
        tester.state<ScrollableState>(nestedScrollables.first).position;
    outerPosition.jumpTo(overlay.metrics.scrollSpaceHeight);
    await tester.pump();

    final firstTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-golden-production-0')),
    );
    expect(firstTile.top, lessThanOrEqualTo(0.5));
    expect(firstTile.bottom, greaterThan(0));
    expect(find.byType(BackdropFilter), findsWidgets);
    await expectLater(
      find.byKey(const Key('production_collapsed_golden')),
      matchesGoldenFile('public_profile_production_collapsed.png'),
    );
  });
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required bool isOfficial,
  required bool collapsed,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _logicalSize * 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(
          size: _logicalSize,
          devicePixelRatio: 3,
          padding: EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: _GoldenProfile(
          key: Key(
            '${isOfficial ? 'official' : 'regular'}_'
            '${collapsed ? 'collapsed' : 'expanded'}_golden',
          ),
          profile: isOfficial ? _officialProfile : _regularProfile,
          collapsed: collapsed,
        ),
      ),
    ),
  );
  await tester.pump();
}

const _officialProfile = PublicProfile(
  id: 'official-profile',
  name: 'Natalo Petshop Official',
  username: 'natalopetshop',
  bio: 'Akun resmi Natalo Petshop & Aquarium 🐾',
  postCount: 128,
  followersCount: 24800,
  followingCount: 86,
  isOfficial: true,
  mutualFollowers: PublicProfileMutualSummary(
    items: [
      PublicProfileMutualFollower(
        id: 'mutual-rani',
        name: 'Rani Anabul Medan',
        username: 'rani.anabul',
      ),
      PublicProfileMutualFollower(
        id: 'mutual-bima',
        name: 'Bima & Mochi',
        username: 'bima.mochi',
      ),
      PublicProfileMutualFollower(
        id: 'mutual-citra',
        name: 'Citra Paw Family',
        username: 'citra.paw',
      ),
    ],
    totalCount: 24,
  ),
);

const _regularProfile = PublicProfile(
  id: 'regular-profile',
  name: 'Mona & Mochi',
  username: 'mona.mochi',
  bio: 'Keseharian dua anabul, camilan favorit, dan tips bermain.',
  postCount: 42,
  followersCount: 1830,
  followingCount: 317,
  mutualFollowers: PublicProfileMutualSummary(
    items: [
      PublicProfileMutualFollower(
        id: 'mutual-henrico',
        name: 'Henrico Julio',
        username: 'henricojulio',
      ),
      PublicProfileMutualFollower(
        id: 'mutual-natsu',
        name: 'Im Natsu',
        username: 'im_natsu',
      ),
    ],
    totalCount: 7,
  ),
);

class _GoldenProfile extends StatefulWidget {
  final PublicProfile profile;
  final bool collapsed;

  const _GoldenProfile({
    super.key,
    required this.profile,
    required this.collapsed,
  });

  @override
  State<_GoldenProfile> createState() => _GoldenProfileState();
}

class _GoldenProfileState extends State<_GoldenProfile>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
    // Chrome and the tab bar now share ONE normalized progress `t` (0 fully
    // expanded, 1 fully collapsed/pinned) instead of a raw pixel
    // scrollOffset — this is the exact same shared value the real
    // NestedScrollView drives both pieces with in production.
    final t = widget.collapsed ? 1.0 : 0.0;
    final motion =
        PublicProfileHeaderMotion.resolve(t: t, reducedMotion: false);
    // Satu layout IG putih untuk semua akun — tidak ada lagi gradient
    // hero navy khusus official.
    final headerDecoration = BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
    );
    // Tab bar rendering moved OUT of PublicProfileChromeOverlay (Task 2) into
    // its own sliver-hosted widget (Task 3). This mock reconstructs it in the
    // exact screen position chrome used to paint it in, using the same
    // motion values. `tabBarContent` itself carries NO enclosing opaque
    // background — matching production's `PublicProfileIdentityTabHeader`,
    // which wraps `PublicProfileContentTabBar` in a bare `SizedBox` only.
    // Individual pills paint their own background via LiquidGlass +
    // `solidFill` (see PublicProfileContentTabBar). Whether the composition
    // reads as opaque or glass-over-grid depends entirely on what the
    // caller wraps THIS in below: the expanded branch nests it inside a
    // DecoratedBox(headerDecoration) that already covers the whole
    // identity+tab column, so it's opaque there just like production
    // (identity block above hasn't scrolled under the grid yet). The
    // collapsed branch must NOT add its own opaque wrapper — in production
    // there the grid is directly behind the tab row, visible through the
    // semi-transparent glass pills.
    final tabBarContent = SizedBox(
      height: metrics.tabHeight,
      child: PublicProfileContentTabBar(
        controller: _controller,
        labelOpacity: motion.labelOpacity,
        pillOpacity: motion.pillOpacity,
        underlineOpacity: motion.underlineOpacity,
      ),
    );

    return RepaintBoundary(
      child: Scaffold(
        body: SizedBox.expand(
          child: Stack(
            children: [
              if (widget.collapsed) ...[
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: RepaintBoundary(
                    child: _DeterministicProfileGrid(),
                  ),
                ),
                Positioned(
                  top: metrics.topPadding + metrics.toolbarHeight,
                  left: 0,
                  right: 0,
                  child: tabBarContent,
                ),
              ] else
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: headerDecoration,
                        child: Column(
                          children: [
                            SizedBox(
                              height:
                                  metrics.topPadding + metrics.toolbarHeight,
                            ),
                            SizedBox(
                              height: metrics.identityHeight,
                              child: PublicProfileExpandedHeader(
                                profile: profile,
                                followBusy: false,
                                chatEnabled: true,
                                onFollowToggle: () {},
                                onShareProfile: () {},
                                onMessage: profile.isOfficial ? () {} : null,
                              ),
                            ),
                            tabBarContent,
                          ],
                        ),
                      ),
                      const RepaintBoundary(
                        child: _DeterministicProfileGrid(),
                      ),
                    ],
                  ),
                ),
              // PublicProfileChromeOverlay.build() returns a bare Positioned
              // itself — it MUST be a direct Stack child, never wrapped in
              // Positioned.fill(...) (throws "Incorrect use of
              // ParentDataWidget").
              PublicProfileChromeOverlay(
                profile: profile,
                t: t,
                metrics: metrics,
                onBack: () {},
                onShareProfile: () {},
                onOverflow: profile.isOfficial ? null : () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpProductionCollapsedGolden(WidgetTester tester) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _logicalSize * 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final posts = List.generate(
    18,
    (index) => FeedPost.fromJson({
      'id': 'golden-production-$index',
      'slug': 'golden-production-$index',
      'kind': index.isEven ? 'USER_VIDEO' : 'USER_IMAGE',
      'videoUrl': index.isEven ? 'invalid-video-$index' : null,
      'thumbnailUrl': 'deterministic-local-placeholder-$index',
      'author': const {
        'id': 'production-profile',
        'name': 'Mona & Mochi',
      },
      'createdAt': DateTime(2026, 7, 16).toIso8601String(),
    }),
  );
  final result = PublicProfileResult(
    profile: _regularProfile,
    posts: posts,
  );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(
          size: _logicalSize,
          devicePixelRatio: 3,
          padding: EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: RepaintBoundary(
          key: const Key('production_collapsed_golden'),
          child: PublicProfileScreen(
            username: 'mona.mochi',
            initialResult: result,
            fetchChatConfig: _noOpFetch,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _noOpFetch() async {}

class _DeterministicProfileGrid extends StatelessWidget {
  static const _colors = <Color>[
    Color(0xFFD6A77A),
    Color(0xFF9CC5A1),
    Color(0xFF6B7D9A),
    Color(0xFFE4C1A3),
    Color(0xFFB5A3C7),
    Color(0xFF678D8B),
    Color(0xFFC98B85),
    Color(0xFF8FA7C2),
    Color(0xFFD7C49E),
    Color(0xFF7E9A8E),
    Color(0xFFBA8F9C),
    Color(0xFF8290A6),
    Color(0xFFD0AA78),
    Color(0xFF789C98),
    Color(0xFFA68A78),
  ];

  const _DeterministicProfileGrid();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _logicalSize.width,
      height: profileGridExtentForWidth(
        _logicalSize.width,
        itemCount: _colors.length,
      ),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: profileGridDelegate(),
        itemCount: _colors.length,
        itemBuilder: (context, index) => DecoratedBox(
          decoration: BoxDecoration(
            color: _colors[index],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _colors[index].withValues(alpha: 0.72),
                _colors[index],
              ],
            ),
          ),
          child: Center(
            child: Icon(
              index.isEven ? Icons.pets_rounded : Icons.photo_camera_outlined,
              size: 34,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
