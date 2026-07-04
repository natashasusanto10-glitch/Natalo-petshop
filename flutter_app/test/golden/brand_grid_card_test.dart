import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/screens/home_screen.dart';
import 'package:natalo_petshop_flutter/models/brand.dart';

/// Golden test untuk `BrandGridCard` — capture render side-by-side untuk
/// logo banner lebar (happy-cat) vs logo kotak (drontal) vs fallback
/// inisial. Fail di future runs kalau:
/// - Logo banner melar mepet tepi lagi (regresi ConstrainedBox height)
/// - Logo kotak balik tenggelam kecil di tengah
/// - Padding kartu berubah tanpa sengaja
///
/// Run:
/// ```bash
/// flutter test --update-goldens test/golden/brand_grid_card_test.dart
/// flutter test test/golden/brand_grid_card_test.dart
/// ```
void main() {
  testWidgets('BrandGridCard renders consistent optical size across logo shapes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 76,
                  child: BrandGridCard(
                    brand: PetBrand(
                      name: 'Happy Cat',
                      color: Color(0xFF1E5FBF),
                      imageAsset: 'assets/brands/happy-cat.png',
                    ),
                    onTap: null,
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  height: 76,
                  child: BrandGridCard(
                    brand: PetBrand(
                      name: 'Drontal',
                      color: Color(0xFF1E5FBF),
                      imageAsset: 'assets/brands/drontal.png',
                    ),
                    onTap: null,
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  height: 76,
                  child: BrandGridCard(
                    brand: PetBrand(
                      name: 'Tanpa Logo',
                      color: Color(0xFF1E5FBF),
                    ),
                    onTap: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('brand_grid_card_states.png'),
    );
  });
}
