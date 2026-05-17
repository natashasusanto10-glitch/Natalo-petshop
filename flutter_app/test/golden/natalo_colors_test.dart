import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/theme/natalo_colors.dart';

/// Golden test — capture snapshot widget render sebagai PNG, fail kalau
/// ada visual regression di future runs.
///
/// Run + generate baseline:
/// ```bash
/// flutter test --update-goldens test/golden/
/// ```
///
/// Run + verify against baseline:
/// ```bash
/// flutter test test/golden/
/// ```
///
/// **Strategi**: Test ini cover **design tokens** (primary colors) — kalau
/// seseorang accidentally ubah `NataloColors.primary` hex, test fail.
/// Pattern lebih cocok untuk komponen visual stable (logo, hero card),
/// kurang cocok untuk screen yang sering iterate.
void main() {
  testWidgets('NataloColors palette renders expected hex', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColorSwatch('primary', NataloColors.primary),
                _ColorSwatch('primaryDark', NataloColors.primaryDark),
                _ColorSwatch('primaryLight', NataloColors.primaryLight),
                _ColorSwatch('success', NataloColors.success),
                _ColorSwatch('warning', NataloColors.warning),
                _ColorSwatch('danger', NataloColors.danger),
                _ColorSwatch('textPrimary', NataloColors.textPrimary),
                _ColorSwatch('textSecondary', NataloColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('natalo_colors_palette.png'),
    );
  });
}

class _ColorSwatch extends StatelessWidget {
  final String name;
  final Color color;

  const _ColorSwatch(this.name, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 60,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
