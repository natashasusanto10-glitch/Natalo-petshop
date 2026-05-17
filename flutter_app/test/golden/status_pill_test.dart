import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:natalo_petshop_flutter/theme/natalo_colors.dart';
import 'package:natalo_petshop_flutter/widgets/app_ui.dart';

/// Golden test untuk `AppStatusPill` — capture render across semantic states
/// (success/warning/danger/primary/muted). Fail di future runs kalau:
/// - Padding/radius/font berubah
/// - Color token shifted
/// - Border treatment diubah
///
/// Run:
/// ```bash
/// flutter test --update-goldens test/golden/status_pill_test.dart
/// flutter test test/golden/status_pill_test.dart
/// ```
void main() {
  testWidgets('AppStatusPill renders all semantic states', (tester) async {
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
                AppStatusPill(label: 'Selesai', color: NataloColors.success),
                AppStatusPill(label: 'Diproses', color: NataloColors.warning),
                AppStatusPill(label: 'Dibatalkan', color: NataloColors.danger),
                AppStatusPill(label: 'Aktif', color: NataloColors.primary),
                AppStatusPill(
                    label: 'Tidak diketahui',
                    color: NataloColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('status_pill_states.png'),
    );
  });
}
