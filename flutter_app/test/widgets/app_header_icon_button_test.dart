import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/theme/natalo_theme.dart';
import 'package:natalo_petshop_flutter/widgets/app_ui.dart';

void main() {
  testWidgets('uses invisible semantics instead of a visual tooltip',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: NataloTheme.lightTheme,
        home: Scaffold(
          body: AppHeaderIconButton(
            tooltip: 'Kembali',
            onPressed: () => taps += 1,
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
    expect(find.bySemanticsLabel('Kembali'), findsOneWidget);

    await tester.longPress(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Kembali'), findsNothing);

    final tapsAfterLongPress = taps;
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(taps, tapsAfterLongPress + 1);

    semantics.dispose();
  });
}
