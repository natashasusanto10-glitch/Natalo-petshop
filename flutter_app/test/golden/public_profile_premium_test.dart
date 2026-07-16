import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/theme/app_theme.dart';
import 'package:natalo_petshop_flutter/theme/natalo_colors.dart';
import 'package:natalo_petshop_flutter/widgets/profile_grid_geometry.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
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
    final scrollOffset = widget.collapsed ? metrics.identityHeight : 0.0;
    final headerDecoration = BoxDecoration(
      color: profile.isOfficial ? null : Theme.of(context).colorScheme.surface,
      gradient: profile.isOfficial ? NataloColors.heroGradientV : null,
    );

    return RepaintBoundary(
      child: Scaffold(
        body: SizedBox.expand(
          child: Stack(
            children: [
              if (widget.collapsed)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: RepaintBoundary(
                    child: _DeterministicProfileGrid(),
                  ),
                )
              else
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
                            SizedBox(height: metrics.tabHeight),
                          ],
                        ),
                      ),
                      const RepaintBoundary(
                        child: _DeterministicProfileGrid(),
                      ),
                    ],
                  ),
                ),
              Positioned.fill(
                child: PublicProfileChromeOverlay(
                  profile: profile,
                  controller: _controller,
                  scrollOffset: scrollOffset,
                  metrics: metrics,
                  onBack: () {},
                  onShareProfile: () {},
                  onOverflow: profile.isOfficial ? null : () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
