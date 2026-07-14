import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/official_brand_avatar.dart';
import 'package:natalo_petshop_flutter/widgets/profile_avatar.dart';

void main() {
  testWidgets('official account always renders Natalo brand avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(
            initial: 'N',
            imageUrl: 'https://example.com/private-owner-photo.jpg',
            isOfficial: true,
          ),
        ),
      ),
    );

    expect(find.byType(OfficialBrandAvatar), findsOneWidget);
    expect(find.text('N'), findsNothing);
  });
}
