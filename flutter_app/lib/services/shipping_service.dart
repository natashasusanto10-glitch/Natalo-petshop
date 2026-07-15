import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import 'api_client.dart';

class ShippingRateResult {
  final List<ShippingRate> rates;
  final String? message;
  final String? instantUnavailableReason;
  final bool fromApi;

  const ShippingRateResult({
    required this.rates,
    this.message,
    this.instantUnavailableReason,
    required this.fromApi,
  });
}

class ShippingService {
  Future<ShippingRateResult> fetchRates({
    required MemberAddress address,
    required List<CartItem> items,
  }) async {
    final areaId = address.areaId?.trim() ?? '';
    if (areaId.isEmpty) {
      return const ShippingRateResult(
        rates: [ShippingRate.selfPickup],
        message: 'Alamat belum punya area pengiriman Biteship.',
        fromApi: false,
      );
    }

    try {
      final data = await apiClient.postJson(
        '/api/shipping/rates',
        body: {
          'destinationAreaId': areaId,
          'destinationPostalCode': address.postalCode,
          'destinationLatitude': address.latitude,
          'destinationLongitude': address.longitude,
          'items': items.map((item) {
            return {
              'name': item.product.title,
              // Gunakan snapshot cart item agar simulasi detail produk dan
              // checkout menghormati harga + berat varian yang dipilih.
              'price': item.unitPrice,
              'weightGram': item.weightGram,
              'quantity': item.quantity,
            };
          }).toList(),
        },
      );
      final rawRates = data['rates'];
      final rates = rawRates is List
          ? rawRates
              .whereType<Map<String, dynamic>>()
              .map(ShippingRate.fromApiJson)
              .where((rate) => rate.available)
              .toList()
          : <ShippingRate>[];

      return ShippingRateResult(
        rates: [ShippingRate.selfPickup, ...rates],
        message: data['message']?.toString(),
        instantUnavailableReason: data['instantUnavailableReason']?.toString(),
        fromApi: true,
      );
    } catch (error) {
      return ShippingRateResult(
        // Jangan menawarkan tarif kurir hard-coded saat API gagal. Checkout
        // hanya boleh mengirim layanan yang telah dikonfirmasi backend.
        rates: const [ShippingRate.selfPickup],
        message: error.toString(),
        fromApi: false,
      );
    }
  }

  /// Search Biteship area dengan keyword (untuk address picker dropdown).
  /// Match endpoint PWA GET /api/shipping/areas?countries=ID&q=Medan
  ///
  /// Return list area dengan id + name + admin breakdown (province/city/etc).
  Future<List<ShippingArea>> fetchAreas({required String query}) async {
    if (query.trim().length < 3) return const [];
    try {
      final data = await apiClient.getJson('/api/shipping/areas', query: {
        'q': query.trim(),
      });
      final raw = data['areas'] ?? data['data'] ?? data['items'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ShippingArea.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Info origin toko (dipakai untuk calculate distance + tariff).
  /// Match endpoint PWA GET /api/shipping/origin.
  /// Returns store lat/lng + area info + postal code.
  Future<ShippingOrigin?> fetchOrigin() async {
    try {
      final data = await apiClient.getJson('/api/shipping/origin');
      return ShippingOrigin.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

/// Biteship area dari pencarian.
class ShippingArea {
  final String id;
  final String name;
  final String? postalCode;
  final String? administrativeDivisionLevel1Name; // Provinsi
  final String? administrativeDivisionLevel2Name; // Kota/Kabupaten
  final String? administrativeDivisionLevel3Name; // Kecamatan
  final String? administrativeDivisionLevel4Name; // Desa/Kelurahan

  const ShippingArea({
    required this.id,
    required this.name,
    this.postalCode,
    this.administrativeDivisionLevel1Name,
    this.administrativeDivisionLevel2Name,
    this.administrativeDivisionLevel3Name,
    this.administrativeDivisionLevel4Name,
  });

  factory ShippingArea.fromJson(Map<String, dynamic> json) {
    return ShippingArea(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['label'] ?? '').toString(),
      postalCode:
          json['postal_code']?.toString() ?? json['postalCode']?.toString(),
      administrativeDivisionLevel1Name:
          json['administrative_division_level_1_name']?.toString() ??
              json['provinceName']?.toString(),
      administrativeDivisionLevel2Name:
          json['administrative_division_level_2_name']?.toString() ??
              json['cityName']?.toString(),
      administrativeDivisionLevel3Name:
          json['administrative_division_level_3_name']?.toString() ??
              json['districtName']?.toString(),
      administrativeDivisionLevel4Name:
          json['administrative_division_level_4_name']?.toString() ??
              json['villageName']?.toString(),
    );
  }
}

/// Info origin toko Natalo (warehouse).
class ShippingOrigin {
  final String? areaId;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? postalCode;

  const ShippingOrigin({
    this.areaId,
    this.address,
    this.latitude,
    this.longitude,
    this.postalCode,
  });

  factory ShippingOrigin.fromJson(Map<String, dynamic> json) {
    return ShippingOrigin(
      areaId: json['areaId']?.toString(),
      address: json['address']?.toString(),
      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : double.tryParse('${json['latitude']}'),
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : double.tryParse('${json['longitude']}'),
      postalCode: json['postalCode']?.toString(),
    );
  }
}

final shippingService = ShippingService();
