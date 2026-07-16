import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/models/cart_item.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/models/shipping_rate.dart';
import 'package:natalo_petshop_flutter/services/shipping_service.dart';
import 'package:natalo_petshop_flutter/widgets/product_detail/product_shipping_section.dart';

void main() {
  test('formatShippingDuration menerjemahkan satuan waktu API ke Indonesia',
      () {
    expect(formatShippingDuration('1–3 Hours'), '1–3 jam');
    expect(formatShippingDuration('2 days'), '2 hari');
    expect(formatShippingDuration('30 minutes'), '30 menit');
    expect(formatShippingDuration('Hari ini'), 'Hari ini');
    expect(formatShippingDuration('-'), '-');
  });

  test('pickPrimaryAddress memilih alamat utama', () {
    const first = MemberAddress(
      id: 'first',
      recipient: 'A',
      phone: '1',
      address: 'Alamat A',
    );
    const primary = MemberAddress(
      id: 'primary',
      recipient: 'B',
      phone: '2',
      address: 'Alamat B',
      isPrimary: true,
    );

    expect(pickPrimaryAddress(const [first, primary])?.id, 'primary');
    expect(pickPrimaryAddress(const []), isNull);
  });

  test('cheapestDeliveryRate mengabaikan pickup dan layanan unavailable', () {
    const unavailable = ShippingRate(
      courierName: 'Kurir A',
      courierCode: 'A',
      serviceName: 'Cepat',
      serviceCode: 'fast',
      serviceType: 'instant',
      price: 5000,
      duration: '1 jam',
      available: false,
    );
    const regular = ShippingRate(
      courierName: 'Kurir B',
      courierCode: 'B',
      serviceName: 'Reguler',
      serviceCode: 'regular',
      serviceType: 'regular',
      price: 10000,
      duration: '2 hari',
      available: true,
    );
    const sameDay = ShippingRate(
      courierName: 'Kurir C',
      courierCode: 'C',
      serviceName: 'Same Day',
      serviceCode: 'same-day',
      serviceType: 'same_day',
      price: 8000,
      duration: 'Hari ini',
      available: true,
    );

    final result = cheapestDeliveryRate(const [
      ShippingRate.selfPickup,
      unavailable,
      regular,
      sameDay,
    ]);
    expect(result?.serviceCode, 'same-day');
  });

  test('alamat tanpa area tidak pernah mendapat tarif kurir fallback',
      () async {
    const address = MemberAddress(
      id: 'address',
      recipient: 'Natalo Member',
      phone: '0812',
      address: 'Medan',
    );
    final product = Product(
      id: 'product',
      title: 'Makanan Kucing',
      slug: 'makanan-kucing',
      category: 'Cat Food',
      brand: 'Natalo',
      description: '',
      price: 25000,
      imageUrl: '',
      weightGram: 500,
      stock: 10,
      rating: 0,
      reviewCount: 0,
    );

    final result = await ShippingService().fetchRates(
      address: address,
      items: [CartItem(product: product, quantity: 1)],
    );

    expect(result.fromApi, isFalse);
    expect(result.rates, hasLength(1));
    expect(result.rates.single.isSelfPickup, isTrue);
  });
}
