import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/widgets/order_tracking_timeline.dart';

Widget _app(Widget child, {double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('pickup DELIVERED reaches the final pickup stage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        OrderTrackingTimeline(
          status: 'DELIVERED',
          createdAt: DateTime.utc(2026, 7, 14),
          type: OrderTimelineType.pickup,
          timelineEvents: [
            OrderTimelineEvent(
              status: 'PROCESSING',
              occurredAt: DateTime.utc(2026, 7, 14, 1),
            ),
            OrderTimelineEvent(
              status: 'READY_FOR_PICKUP',
              occurredAt: DateTime.utc(2026, 7, 14, 2),
            ),
          ],
          pickedUpAt: DateTime.utc(2026, 7, 14, 3),
        ),
      ),
    );

    expect(find.text('Status Pengambilan'), findsOneWidget);
    expect(find.text('Siap diambil'), findsOneWidget);
    expect(find.text('Diambil dan selesai'), findsOneWidget);
    expect(find.text('14 Jul 2026, 10.00 WIB'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
  });

  testWidgets('delivery uses shipped and delivered lifecycle', (tester) async {
    await tester.pumpWidget(
      _app(
        OrderTrackingTimeline(
          status: 'SHIPPED',
          createdAt: DateTime.utc(2026, 7, 14),
          type: OrderTimelineType.delivery,
          shippedAt: DateTime.utc(2026, 7, 14, 5),
        ),
      ),
    );

    expect(find.text('Dikirim'), findsOneWidget);
    expect(find.text('Diterima dan selesai'), findsOneWidget);
    expect(find.text('14 Jul 2026, 12.00 WIB'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
  });

  testWidgets('legacy order does not fabricate missing timestamps', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        OrderTrackingTimeline(
          status: 'PROCESSING',
          createdAt: DateTime.utc(2026, 7, 14),
          type: OrderTimelineType.pickup,
        ),
        textScale: 1.8,
      ),
    );

    expect(find.text('Waktu belum tersedia'), findsOneWidget);
    expect(find.text('Menunggu proses'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled order exposes an accessible status', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        OrderTrackingTimeline(
          status: 'CANCELLED',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Pesanan dibatalkan'), findsOneWidget);
    semantics.dispose();
  });
}
