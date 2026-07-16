import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/widgets/bottom_nav.dart';

void main() {
  testWidgets('member profile retains account bottom navigation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    expect(find.byType(BottomNavBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
