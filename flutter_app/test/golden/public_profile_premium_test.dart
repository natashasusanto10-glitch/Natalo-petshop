import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/theme/app_theme.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_content_tab_bar.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:visibility_detector/visibility_detector.dart';

const _logicalSize = Size(393, 852);

/// Golden layout profil publik — layout STATIS baru (AppBar tetap + header
/// identitas sebagai sliver biasa + tab bar pinned). Mesin collapse/glass
/// lama sudah dibuang, jadi golden merender langsung layar produksi.
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

  testWidgets('official profile top of scroll iPhone 15 Pro', (tester) async {
    await _pumpScreen(tester, profile: _officialProfile);
    await expectLater(
      find.byKey(const Key('public_profile_golden')),
      matchesGoldenFile('public_profile_official_expanded.png'),
    );
  });

  testWidgets('regular profile top of scroll iPhone 15 Pro', (tester) async {
    await _pumpScreen(tester, profile: _regularProfile);
    await expectLater(
      find.byKey(const Key('public_profile_golden')),
      matchesGoldenFile('public_profile_regular_expanded.png'),
    );
  });

  testWidgets('regular profile scrolled: header gone, tab pinned under app bar',
      (tester) async {
    await _pumpScreen(tester, profile: _regularProfile, withGrid: true);

    final nestedScrollables = find.descendant(
      of: find.byType(NestedScrollView),
      matching: find.byType(Scrollable),
    );
    final outerPosition =
        tester.state<ScrollableState>(nestedScrollables.first).position;
    final headerHeight =
        tester.getSize(find.byType(PublicProfileExpandedHeader)).height;
    outerPosition.jumpTo(headerHeight + 200);
    await tester.pump();

    // Kontrak layout statis: AppBar tetap, tab bar pinned tepat di bawahnya,
    // dan tidak ada BackdropFilter (glass) di tree.
    final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
    final tabTop = tester.getRect(find.byType(PublicProfileContentTabBar)).top;
    expect(tabTop, closeTo(appBarBottom, 0.5));
    expect(find.byType(BackdropFilter), findsNothing);

    await expectLater(
      find.byKey(const Key('public_profile_golden')),
      matchesGoldenFile('public_profile_regular_collapsed.png'),
    );
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required PublicProfile profile,
  bool withGrid = false,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _logicalSize * 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final posts = withGrid
      ? List.generate(
          18,
          (index) => FeedPost.fromJson({
            'id': 'golden-$index',
            'slug': 'golden-$index',
            'kind': index.isEven ? 'USER_VIDEO' : 'USER_IMAGE',
            'videoUrl': index.isEven ? 'invalid-video-$index' : null,
            'thumbnailUrl': 'deterministic-local-placeholder-$index',
            'author': {'id': profile.id, 'name': profile.name},
            'createdAt': DateTime(2026, 7, 16).toIso8601String(),
          }),
        )
      : const <FeedPost>[];

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
          key: const Key('public_profile_golden'),
          child: PublicProfileScreen(
            username: profile.username ?? profile.id,
            initialResult: PublicProfileResult(profile: profile, posts: posts),
            fetchChatConfig: _noOpFetch,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _noOpFetch() async {}

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
