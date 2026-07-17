import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';

Future<double> _gapFor(WidgetTester tester, PublicProfile profile,
    {double textScale = 1.0}) async {
  late double allocated;
  await tester.pumpWidget(MaterialApp(
    // RENDERED header WAJIB pakai font yang sama dengan yang diukur
    // TextPainter (PlusJakartaSans) — kalau tidak, test dan produksi
    // sepakat pada font salah dan bug wrap-count lolos.
    theme: ThemeData(
      fontFamily: 'PlusJakartaSans',
      fontFamilyFallback: const ['Roboto', 'Arial'],
    ),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(393, 852),
        padding: const EdgeInsets.only(top: 59, bottom: 34),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(builder: (context) {
        allocated =
            PublicProfileHeaderMetrics.resolve(context, profile).identityHeight;
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 393,
              child: IntrinsicHeight(
                child: PublicProfileExpandedHeader(
                  profile: profile,
                  followBusy: false,
                  chatEnabled: true,
                  // Wire the same callbacks the real screen always passes
                  // (see identityMetricsHarness in
                  // public_profile_chrome_overlay_test.dart) — without
                  // them _ActionRow renders zero buttons (0 height),
                  // which is not a state real screens ever reach and
                  // would make this measurement meaningless.
                  onFollowToggle: () {},
                  onShareProfile: () {},
                  onMessage: () {},
                ),
              ),
            ),
          ),
        );
      }),
    ),
  ));
  final content =
      tester.getSize(find.byType(PublicProfileExpandedHeader)).height;
  return allocated - content;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final textFontLoader = FontLoader('PlusJakartaSans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans[wght].ttf'));
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([textFontLoader.load(), iconFontLoader.load()]);
  });

  const officialShortBio = PublicProfile(
    id: 'o', name: 'Natalo Petshop Official', username: 'natalopetshop',
    bio: 'Akun resmi Natalo Petshop & Aquarium', isOfficial: true,
    isFollowing: true, postCount: 17, followersCount: 1, followingCount: 1,
  );
  const regularShortBio = PublicProfile(
    id: 'r', name: 'Mona', username: 'mona', bio: 'Cat mom',
    postCount: 3, followersCount: 5, followingCount: 9,
  );
  const regularLongBio = PublicProfile(
    id: 'r2', name: 'Mona', username: 'mona',
    bio: 'Keseharian dua anabul, camilan favorit, tips bermain, dan cerita '
        'lucu setiap hari yang panjang sampai dua baris penuh pasti',
    postCount: 3, followersCount: 5, followingCount: 9,
  );

  // Bio yang duduk tepat di batas wrap 1-vs-2 baris di Jakarta Sans pada
  // lebar 393−32=361px. Di font default test glyph lebih rapat → muat 1
  // baris → TextPainter (kalau salah font) under-measure ~18px → clip.
  const regularBoundaryBio = PublicProfile(
    id: 'rb', name: 'Mona', username: 'mona',
    bio: 'Anabul lucu suka main air dan camilan enak tiap hari',
    postCount: 3, followersCount: 5, followingCount: 9,
  );

  for (final (label, profile) in [
    ('official short bio', officialShortBio),
    ('regular short bio', regularShortBio),
    ('regular long bio', regularLongBio),
    ('regular boundary bio', regularBoundaryBio),
  ]) {
    testWidgets('gap $label is tight and non-negative', (tester) async {
      final gap = await _gapFor(tester, profile);
      expect(gap, greaterThanOrEqualTo(0),
          reason: '$label: konten tidak boleh ter-clip (gap<0)');
      expect(gap, lessThanOrEqualTo(14),
          reason: '$label: rongga harus rapat (≤14px)');
    });
  }

  testWidgets('gap official at text-scale 1.3 stays non-negative',
      (tester) async {
    final gap = await _gapFor(tester, officialShortBio, textScale: 1.3);
    expect(gap, greaterThanOrEqualTo(0));
  });
}
