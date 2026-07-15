import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';

void main() {
  testWidgets('shows an origin snapshot when a keyed source is mounted', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(_buildSource(key));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: key,
        destinationBuilder: (_) => const Placeholder(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );
  });

  testWidgets('shows the destination when the keyed source is unavailable', (
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
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsNothing,
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
          child: SizedBox(key: key),
        ),
      ),
    ),
  );
}
