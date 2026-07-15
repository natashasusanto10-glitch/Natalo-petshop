import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';

void main() {
  testWidgets('shows a captured static snapshot when the source is a boundary',
      (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(_buildSource(key));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: key,
        snapshotImageUrl: 'https://example.com/never-fetched.jpg',
        destinationBuilder: (_) => const Placeholder(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('uses a reversible fade when the source boundary is unavailable',
      (
    tester,
  ) async {
    await tester.pumpWidget(_buildSource(GlobalKey()));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: GlobalKey(),
        destinationBuilder: (_) => const Text('Composer'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Composer'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('origin-expansion-fade')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 240));
    Navigator.of(tester.element(find.byKey(const ValueKey('route-context'))))
        .pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    expect(
      find.byKey(const ValueKey('origin-expansion-fade')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FadeTransition>(
            find.byKey(const ValueKey('origin-expansion-fade')),
          )
          .opacity
          .value,
      lessThan(1),
    );
  });
}

Widget _buildSource(GlobalKey key) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => SizedBox(
          key: const ValueKey('route-context'),
          width: 80,
          height: 80,
          child: RepaintBoundary(
            key: key,
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    ),
  );
}
