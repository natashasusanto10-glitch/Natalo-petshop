import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/natalo_paw_refresh_indicator.dart';

void main() {
  testWidgets('full-pull mode ignores short pulls and accepts deliberate pull',
      (tester) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NataloPawRefreshIndicator(
            triggerOffset: 96,
            maxChildOffset: 104,
            requireFullPull: true,
            onRefresh: () async => refreshCount++,
            child: ListView(
              key: const Key('profile-scroll'),
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const Key('profile-scroll')),
      const Offset(0, 50),
    );
    await tester.pumpAndSettle();
    expect(refreshCount, 0);

    await tester.drag(
      find.byKey(const Key('profile-scroll')),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();
    expect(refreshCount, 1);
  });
}
