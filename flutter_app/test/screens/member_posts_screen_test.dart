import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/member_posts_screen.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MemberPostsScreen()));
    // Bounded pump-loop (bukan pumpAndSettle) — fetch jaringan gagal cepat
    // di test env; loop menunggu state loading selesai tanpa risiko hang.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  testWidgets('own profile renders IG-style header with owner actions',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PublicProfileExpandedHeader), findsOneWidget);
    expect(find.text('Edit Profil'), findsOneWidget);
    expect(find.text('Bagikan Profil'), findsOneWidget);
    // Owner tidak pernah melihat tombol follow/pesan di profil sendiri.
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Pesan'), findsNothing);
    // Stats horizontal ala IG.
    expect(find.text('Postingan'), findsOneWidget);
    expect(find.text('Pengikut'), findsOneWidget);
    expect(find.text('Mengikuti'), findsOneWidget);
  });

  testWidgets('filter tabs render as IG icon tabs with semantics',
      (tester) async {
    await pumpScreen(tester);

    for (final label in const ['Semua', 'Foto', 'Video', 'Menunggu']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    // Tab pertama aktif by default.
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Semua'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.selected, isTrue);

    await tester.tap(find.byTooltip('Video'));
    await tester.pump();
    final videoSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(videoSemantics.properties.selected, isTrue);
  });
}
