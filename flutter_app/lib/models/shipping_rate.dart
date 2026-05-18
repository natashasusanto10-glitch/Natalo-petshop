class ShippingRate {
  final String courierName;
  final String courierCode;
  final String serviceName;
  final String serviceCode;
  final String serviceType;
  final int price;
  final String duration;
  final bool available;
  final String? unavailableReason;
  final String? description;

  const ShippingRate({
    required this.courierName,
    required this.courierCode,
    required this.serviceName,
    required this.serviceCode,
    required this.serviceType,
    required this.price,
    required this.duration,
    required this.available,
    this.unavailableReason,
    this.description,
  });

  factory ShippingRate.fromApiJson(Map<String, dynamic> json) {
    return ShippingRate(
      courierName: (json['courier_name'] ?? 'Kurir').toString(),
      courierCode: (json['courier_code'] ?? '').toString(),
      serviceName: (json['courier_service_name'] ?? 'Reguler').toString(),
      serviceCode: (json['courier_service_code'] ?? '').toString(),
      serviceType: (json['service_type'] ?? 'regular').toString(),
      price: _asInt(json['price']),
      duration: (json['duration'] ?? '-').toString(),
      available: json['available'] != false,
      unavailableReason: json['unavailable_reason']?.toString(),
      description: json['description']?.toString(),
    );
  }

  String get label {
    if (isSelfPickup) return courierName;
    return '$courierName $serviceName';
  }

  bool get isSelfPickup => courierCode == 'SELF_PICKUP';

  static const selfPickup = ShippingRate(
    courierName: 'Ambil Sendiri di Toko',
    courierCode: 'SELF_PICKUP',
    serviceName: 'Gratis ongkir',
    serviceCode: 'SELF_PICKUP',
    serviceType: 'pickup',
    price: 0,
    duration: '09.00 - 17.00 WIB',
    available: true,
    description:
        'Natalo Petshop / Sinar Petstore, Jln MT. Haryono No 103 B C D, Pusat Pasar, Medan Kota.',
  );
}

class PickupStoreInfo {
  static const id = 'store_mt_haryono';
  static const name = 'Natalo Petshop / Sinar Petstore';
  static const address =
      'Jln MT. Haryono No 103 B C D, Pusat Pasar, Medan Kota';
  static const hours = '09.00 - 17.00 WIB';
  static const mapsUrl =
      'https://www.google.com/maps/search/?api=1&query=Natalo%20Petshop%20Sinar%20Petstore%20Jln%20MT%20Haryono%20No%20103%20B%20C%20D%20Pusat%20Pasar%20Medan%20Kota';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
