import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/app_chat_button.dart';

void main() {
  testWidgets('explicit chat icon size survives a tight action frame',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 36,
            child: ChatDotsBubbleIcon(size: 18),
          ),
        ),
      ),
    );

    final paint = find.descendant(
      of: find.byType(ChatDotsBubbleIcon),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint), const Size.square(18));
  });
}
