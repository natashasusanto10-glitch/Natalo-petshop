import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_viewer_route.dart';

void main() {
  Future<void> pumpGridWithViewer(WidgetTester tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text('grid'))),
    ));
    navKey.currentState!.push(PostViewerRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('viewer'))),
    ));
    // Selesaikan transisi push sampai tuntas.
    await tester.pumpAndSettle();
  }

  testWidgets(
      'drag tepi-kiri melewati ambang MEMUTUP route (viewer hilang, grid balik)',
      (tester) async {
    await pumpGridWithViewer(tester);
    expect(find.text('viewer'), findsOneWidget);

    // Mulai dari tepi kiri (x kecil), seret jauh ke kanan melewati mid-screen.
    final Size size = tester.getSize(find.byType(MaterialApp));
    final gesture = await tester.startGesture(Offset(5, size.height / 2));
    await tester.pump();
    await gesture.moveBy(Offset(size.width * 0.8, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsNothing);
    expect(find.text('grid'), findsOneWidget);
  });

  testWidgets('drag kecil di bawah ambang TIDAK memutup route (viewer tetap)',
      (tester) async {
    await pumpGridWithViewer(tester);
    expect(find.text('viewer'), findsOneWidget);

    final Size size = tester.getSize(find.byType(MaterialApp));
    final gesture = await tester.startGesture(Offset(5, size.height / 2));
    await tester.pump();
    // Geser hanya sedikit (jauh di bawah 50% dan tanpa fling).
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('viewer'), findsOneWidget);
  });

  testWidgets('popGestureEnabled false selagi transisi push masih beranimasi',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()),
    ));
    final route = PostViewerRoute<void>(
      builder: (_) => const Scaffold(body: Text('viewer')),
    );
    navKey.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // mid-transisi

    expect(route.animation!.status, isNot(AnimationStatus.completed));
    // Tepi kiri tak boleh memutup saat masih beranimasi masuk.
    final gesture = await tester.startGesture(const Offset(5, 400));
    await tester.pump();
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    await gesture.up();
    // Selesaikan; kalau gestur di-abaikan, route tetap ada setelah settle push.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('viewer'), findsOneWidget);
  });

  testWidgets('route memakai FadeTransition (regresi: bukan slide/Material)',
      (tester) async {
    final route = PostViewerRoute<void>(builder: (_) => const SizedBox());
    expect(route, isNot(isA<MaterialPageRoute<void>>()));
    expect(route.opaque, isTrue);
    expect(route.maintainState, isTrue);

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()),
    ));
    navKey.currentState!.push(PostViewerRoute<void>(
      builder: (_) => const Scaffold(body: Text('viewer')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.ancestor(
        of: find.text('viewer'),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    // Tidak ada SlideTransition milik route (fade murni).
    expect(
      find.ancestor(
        of: find.text('viewer'),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 400));
  });
}
