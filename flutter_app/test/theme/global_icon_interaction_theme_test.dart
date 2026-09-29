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

    test(
        '${entry.key} theme gives IconButtons a pressed overlay '
        '(press feedback tanpa ripple)', () {
      final overlay = entry.value.iconButtonTheme.style?.overlayColor;

      expect(overlay, isNotNull);
      // Pressed & hovered → tint terlihat (feedback). State lain (focused,
      // default) → transparan. Sebelumnya SEMUA transparan yang membuat
      // seluruh IconButton app-wide tidak merespons tekanan.
      final pressed = overlay!.resolve(const <WidgetState>{
        WidgetState.pressed,
      });
      final hovered = overlay.resolve(const <WidgetState>{
        WidgetState.hovered,
      });
      expect(pressed, isNot(Colors.transparent));
      expect(hovered, isNot(Colors.transparent));
      expect(
        overlay.resolve(const <WidgetState>{WidgetState.focused}),
        Colors.transparent,
      );
      expect(
        overlay.resolve(const <WidgetState>{}),
        Colors.transparent,
      );
    });
  }
}
