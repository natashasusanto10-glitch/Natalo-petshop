import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_order_detail_screen.dart';

OrderSummary _order({
  String orderType = 'DELIVERY',
  String shippingMethod = 'DELIVERY',
  String customerName = 'Rani Wijaya',
  String customerPhone = '081234567890',
  String shippingAddress = 'Jl. Melati No. 12, RT 03/RW 05',
  String? shippingCity = 'Bandung',
  String status = 'PROCESSING',
}) {
  return OrderSummary(
    id: 'order-1',
    orderNumber: 'ORD-ADDR-001',
    status: status,
    paymentStatus: 'PAID',
    createdAt: DateTime(2026, 7, 20, 9),
    total: 150000,
    orderType: orderType,
    shippingMethod: shippingMethod,
    customerName: customerName,
    customerPhone: customerPhone,
    shippingAddress: shippingAddress,
    shippingCity: shippingCity,
    items: [
      OrderItemSummary(
        id: 'item-1',
        productId: 'product-1',
        name: 'Makanan Kucing Natalo',
        price: 150000,
        quantity: 1,
      ),
    ],
  );
}

Widget _host(OrderSummary order) {
  return MaterialApp(home: MemberOrderDetailScreen(order: order));
}

/// Halaman detail memakai scroll view lazy — dengan viewport setinggi ponsel,
/// kartu alamat ada di bawah lipatan dan TIDAK ikut terbangun, sehingga finder
/// apa pun akan meleset. Viewport tinggi bikin seluruh halaman terbangun.
///
/// `pumpAndSettle` juga hang di app ini (timeline pesanan menganimasi terus),
/// jadi pakai pump berbatas.
Future<void> _pumpScreen(WidgetTester tester, OrderSummary order) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(_host(order));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('pesanan kirim menampilkan alamat, penerima, dan kota',
      (tester) async {
    await _pumpScreen(tester, _order());

    expect(find.text('Alamat Pengiriman'), findsOneWidget);
    expect(find.text('Penerima'), findsOneWidget);
    expect(find.text('Rani Wijaya\n081234567890'), findsOneWidget);
    expect(
      find.text('Jl. Melati No. 12, RT 03/RW 05\nBandung'),
      findsOneWidget,
    );
  });

  testWidgets('kota tidak diulang kalau sudah tertulis di dalam alamat',
      (tester) async {
    await _pumpScreen(
      tester,
      _order(
        shippingAddress: 'Jl. Melati No. 12, Bandung',
        shippingCity: 'Bandung',
      ),
    );

    expect(find.text('Jl. Melati No. 12, Bandung'), findsOneWidget);
    expect(find.text('Jl. Melati No. 12, Bandung\nBandung'), findsNothing);
  });

  testWidgets('pesanan ambil sendiri TIDAK menampilkan kartu alamat kirim',
      (tester) async {
    await _pumpScreen(
      tester,
      _order(orderType: 'PICKUP', shippingMethod: 'SELF_PICKUP'),
    );

    expect(find.text('Alamat Pengiriman'), findsNothing);
  });

  testWidgets('alamat kosong tidak memunculkan kartu setengah terisi',
      (tester) async {
    await _pumpScreen(tester, _order(shippingAddress: '   '));

    expect(find.text('Alamat Pengiriman'), findsNothing);
  });

  testWidgets(
      'alamat tampil sejak pesanan masih menunggu bayar — bukan hanya setelah '
      'dikirim (justru saat itu user masih sempat koreksi)', (tester) async {
    await _pumpScreen(tester, _order(status: 'UNPAID'));

    expect(find.text('Alamat Pengiriman'), findsOneWidget);
  });

  testWidgets('penerima tanpa nama/telepon: baris Penerima disembunyikan, '
      'alamat tetap tampil', (tester) async {
    await _pumpScreen(tester, _order(customerName: '', customerPhone: ''));

    expect(find.text('Alamat Pengiriman'), findsOneWidget);
    expect(find.text('Penerima'), findsNothing);
    expect(find.text('Alamat'), findsOneWidget);
  });
}
