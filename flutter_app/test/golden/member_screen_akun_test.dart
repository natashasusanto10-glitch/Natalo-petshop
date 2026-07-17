import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _logicalSize = Size(393, 852);

/// Bukti visual: tab Akun (profil sendiri) direombak dari hero navy ke
/// layout putih IG-style yang sama dengan profil publik. Ikon top bar
/// (+, tersimpan, notifikasi, pengaturan) dipertahankan; hanya direcolor
/// gelap + username ditambahkan di tengah.
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
    SharedPreferences.setMockInitialValues(const {});
    memberStore.setProfile(
      const MemberProfile(
        id: 'owner-1',
        name: 'Natasha',
        username: 'natasha_s',
        role: 'CUSTOMER',
        bio: 'Cat mom di Jakarta 🐾',
        followersCount: 24,
        followingCount: 31,
      ),
    );
  });

  tearDown(() async {
    await memberStore.logout();
  });

  testWidgets('own profile (Akun tab) renders IG-white iPhone 15 Pro',
      (tester) async {
    tester.view.physicalSize = _logicalSize * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }

    await expectLater(
      find.byType(MemberScreen),
      matchesGoldenFile('member_screen_akun_ig_white.png'),
    );
  });
}
