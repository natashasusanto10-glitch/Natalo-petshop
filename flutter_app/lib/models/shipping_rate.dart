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
    duration: '10.00 - 20.00 WIB',
    available: true,
    description: 'Ambil pesanan langsung di Natalo Petshop.',
  );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
