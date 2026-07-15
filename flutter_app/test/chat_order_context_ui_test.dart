import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/chat_message.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_order_detail_screen.dart';
import 'package:natalo_petshop_flutter/widgets/chat/chat_bubble.dart';
import 'package:natalo_petshop_flutter/widgets/chat/chat_composer.dart';

void main() {
  testWidgets('order context tetap compact di layar kecil dan font besar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: ChatContextChip(
                isCustomer: false,
                order: ChatOrderRef(
                  orderNumber: 'ORD-20260715-NOMOR-SANGAT-PANJANG',
                  status: 'PENDING',
                  paymentProofStatus: 'PENDING_REVIEW',
                  total: 2983946,
                  itemCount: 4,
                  hasPaymentProof: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('PESANAN'), findsOneWidget);
    expect(find.textContaining('Menunggu verifikasi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ChatContextChip)).width, lessThan(260));
  });

  testWidgets('composer dapat kirim context tanpa teks', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? sent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            onAttachPhoto: () {},
            onSend: (value) => sent = value,
            canSendWithoutText: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-send')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    expect(sent, '');
  });

  testWidgets('composer tanpa teks dan tanpa context tetap tidak dapat kirim',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            onAttachPhoto: () {},
            onSend: (_) => fail('tidak boleh terkirim'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-send')), findsNothing);
    expect(find.byKey(const ValueKey('chat-send-empty')), findsOneWidget);
  });

  testWidgets('bukti ditolak tampil sebagai upload ulang, bukan menunggu',
      (tester) async {
    final order = OrderSummary(
      id: 'order-rejected',
      orderNumber: 'ORD-REJECTED',
      status: 'PENDING',
      paymentStatus: 'UNPAID',
      paymentProvider: 'MANUAL',
      paymentProofUrl: 'https://cdn.example/proof.jpg',
      paymentProofStatus: 'REJECTED',
      createdAt: DateTime(2026, 7, 15),
      total: 125000,
    );

    await tester.pumpWidget(
      MaterialApp(home: MemberOrderDetailScreen(order: order)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Bukti Perlu Diperbarui'),
      350,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Bukti Perlu Diperbarui'), findsOneWidget);
    expect(find.text('Upload Ulang'), findsOneWidget);
    expect(find.text('Menunggu Verifikasi'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
