import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';

/// Harness: home + tombol buka viewer via pushOriginExpansion (originKey
/// tidak ter-attach → jalur fade-only, cukup untuk menguji mesin dismiss).
class _Harness extends StatelessWidget {
  const _Harness({required this.navKey, required this.onHomeTap});
  final GlobalKey<NavigatorState> navKey;
  final VoidCallback onHomeTap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const ValueKey('home-tap-probe'),
                onPressed: onHomeTap,
                child: const Text('probe'),
              ),
              Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-viewer'),
                  onPressed: () => pushOriginExpansion<void>(
                    context,
                    originKey: GlobalKey(),
                    destinationBuilder: (_) => const Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(
                        child: Text('VIEWER',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-viewer')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350)); // buka 300ms selesai
  expect(find.text('VIEWER'), findsOneWidget);
}

void main() {
  late List<AnimationStatus> statuses;

  setUp(() {
    statuses = [];
    debugOriginExpansionStatusObserver = (status, _) => statuses.add(status);
  });

  tearDown(() => debugOriginExpansionStatusObserver = null);

  testWidgets('pop programatik saat drag aktif → route tetap tuntas tertutup',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var probeTaps = 0;
    await tester.pumpWidget(
        _Harness(navKey: navKey, onHomeTap: () => probeTaps++));
    await _openViewer(tester);

    // Mulai drag tepi kiri.
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    // Pop datang dari sumber lain (tombol back AppBar / back sistem).
    navKey.currentState!.pop();
    await tester.pump();

    // Jari masih bergerak lalu lepas — dulu ini membekukan animasi.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();

    // Beri waktu animasi penutup selesai (reverse 250ms) + finalisasi.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('VIEWER'), findsNothing,
        reason: 'viewer tidak boleh menyisa (ghost)');
    expect(statuses.last, AnimationStatus.dismissed,
        reason: 'route wajib mencapai dismissed (I1)');
    // Barrier tidak boleh menyisa menelan input.
    await tester.tap(find.byKey(const ValueKey('home-tap-probe')));
    expect(probeTaps, 1);
  });

  testWidgets(
      'drag mentok penuh lalu lepas → route terfinalisasi, tanpa '
      'barrier menyisa', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var probeTaps = 0;
    await tester.pumpWidget(
        _Harness(navKey: navKey, onHomeTap: () => probeTaps++));
    await _openViewer(tester);

    final width =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final gesture = await tester.startGesture(const Offset(10, 300));
    // Drag melebihi lebar layar → tanpa clamp, nilai menyentuh 0 pra-pop.
    await gesture.moveBy(Offset(width + 200, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('VIEWER'), findsNothing);
    expect(statuses.last, AnimationStatus.dismissed);
    await tester.tap(find.byKey(const ValueKey('home-tap-probe')));
    expect(probeTaps, 1, reason: 'input tidak boleh dimakan barrier mati');
  });

  testWidgets('drag tanggung lalu lepas → spring back, viewer utuh',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_Harness(navKey: navKey, onHomeTap: () {}));
    await _openViewer(tester);

    final gesture = await tester.startGesture(const Offset(10, 300));
    // Drag PELAN multi-langkah (< 25% lebar, velocity jauh di bawah ambang
    // fling 800 px/s) — satu moveBy besar dalam satu frame bisa terbaca
    // sebagai fling oleh VelocityTracker → flaky pop, bukan spring back.
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    // Beberapa pump: pump pertama setelah animateWith hanya menjadi tick
    // epoch ticker (t=0) — pegas butuh frame-frame berikutnya untuk maju.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('VIEWER'), findsOneWidget);
    expect(statuses.last, AnimationStatus.completed,
        reason: 'spring back wajib berakhir completed (I2)');
  });

  testWidgets('drag tepi saat animasi BUKA berjalan → tidak membekukan buka',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_Harness(navKey: navKey, onHomeTap: () {}));
    await tester.tap(find.byKey(const ValueKey('open-viewer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // buka masih jalan

    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(statuses.last, AnimationStatus.completed,
        reason: 'animasi buka wajib mencapai completed (I3)');
    expect(find.text('VIEWER'), findsOneWidget);
  });
}
