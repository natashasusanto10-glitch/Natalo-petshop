import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tab Akun (profil sendiri) — direombak jadi IG-white sesuai
/// `PublicProfileExpandedHeader` bersama. Ikon top bar (buat postingan,
/// tersimpan, notifikasi, pengaturan) TIDAK berubah bentuk/logika — hanya
/// direcolor gelap + username ditambahkan di tengah bar.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    memberStore.setProfile(
      const MemberProfile(
        id: 'owner-1',
        name: 'Natasha',
        username: 'natasha_s',
        role: 'CUSTOMER',
        bio: 'Cat mom di Jakarta',
        followersCount: 24,
        followingCount: 31,
      ),
    );
  });

  tearDown(() async {
    await memberStore.logout();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    // Bounded pump-loop — fetch jaringan gagal cepat di test env; loop
    // menunggu state loading selesai tanpa risiko hang (pumpAndSettle bisa
    // hang kalau ada retry/animasi berjalan terus).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  testWidgets('own profile reuses shared IG-style header with owner actions',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PublicProfileExpandedHeader), findsOneWidget);
    expect(find.text('Edit Profil'), findsOneWidget);
    expect(find.text('Bagikan Profil'), findsOneWidget);
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Pesan'), findsNothing);
  });

  testWidgets('top bar keeps every existing icon unchanged', (tester) async {
    await pumpScreen(tester);

    expect(find.byTooltip('Buat postingan'), findsOneWidget);
    expect(find.byTooltip('Postingan tersimpan'), findsOneWidget);
    expect(find.byTooltip('Pengaturan akun'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('username renders centered in the top bar', (tester) async {
    await pumpScreen(tester);

    expect(find.text('natasha_s'), findsOneWidget);
  });

  testWidgets('status bar uses dark icons over the white header',
      (tester) async {
    await pumpScreen(tester);

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value, SystemUiOverlayStyle.dark);
  });

  testWidgets('content tabs render without a full-width underline bar',
      (tester) async {
    await pumpScreen(tester);

    // Sistem tab profil publik yang baru: ikon saja + indikator pendek di
    // bawah tab aktif (bukan garis full-width UnderlineTabIndicator lama).
    expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_video_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_shop_pill')), findsOneWidget);
  });
}
