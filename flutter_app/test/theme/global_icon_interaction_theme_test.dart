import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/theme/natalo_theme.dart';

void main() {
  for (final entry in <String, ThemeData>{
    'light': NataloTheme.lightTheme,
    'dark': NataloTheme.darkTheme,
  }.entries) {
    testWidgets('${entry.key} theme keeps icon semantics without visual tooltip',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: entry.value,
          home: Scaffold(
            body: IconButton(
              tooltip: 'Bagikan',
              onPressed: () => taps += 1,
              icon: const Icon(Icons.share_outlined),
            ),
          ),
        ),
      );

      await tester.longPress(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Bagikan'), findsNothing);

      final tapsAfterLongPress = taps;
      await tester.tap(find.byIcon(Icons.share_outlined));
      expect(taps, tapsAfterLongPress + 1);
    });

    test('${entry.key} theme makes every IconButton overlay transparent', () {
      final overlay = entry.value.iconButtonTheme.style?.overlayColor;

      expect(overlay, isNotNull);
      for (final state in <WidgetState>{
        WidgetState.pressed,
        WidgetState.hovered,
        WidgetState.focused,
      }) {
        expect(overlay!.resolve(<WidgetState>{state}), Colors.transparent);
      }
    });
  }
}
