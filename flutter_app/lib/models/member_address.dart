/// Member address — match Prisma Address (lihat schema.prisma).
/// Stub minimal sampai shipping_service di-port complete.
class MemberAddress {
  final String id;
  final String? label;
  final String recipient;
  final String phone;
  final String address;
  final String? city;
  final String? postalCode;
  final String? areaId;
  final String? areaLabel;
  final String? provinceName;
  final String? cityName;
  final String? districtName;
  final bool isMain;
  final double? latitude;
  final double? longitude;
  final String? pinpointAddress;
  final String? streetName;

  const MemberAddress({
    required this.id,
    this.label,
    required this.recipient,
    required this.phone,
    required this.address,
    this.city,
    this.postalCode,
    this.areaId,
    this.areaLabel,
    this.provinceName,
    this.cityName,
    this.districtName,
    bool isMain = false,
    bool? isPrimary,
    this.latitude,
    this.longitude,
    this.pinpointAddress,
    this.streetName,
  }) : isMain = isPrimary ?? isMain;

  factory MemberAddress.fromJson(Map<String, dynamic> json) {
    final id = _firstString(json['id'], json['_id']);
    return MemberAddress(
      id: id,
      label: _nullableString(json['label']),
      recipient: _firstString(
        json['recipient'],
        json['recipientName'],
        json['recipient_name'],
        json['nama'],
      ),
      phone: _firstString(json['phone'], json['phoneNumber'], json['noHp']),
      address: _firstString(
        json['address'],
        json['street'],
        json['jalan'],
        json['shippingAddress'],
      ),
      city: _nullableString(json['city'] ?? json['kota']),
      postalCode: _nullableString(
        json['postalCode'] ?? json['postal_code'] ?? json['kodePos'],
      ),
      areaId: _nullableString(json['areaId'] ?? json['area_id']),
      areaLabel: _nullableString(json['areaLabel'] ?? json['area_label']),
      provinceName: _nullableString(
        json['provinceName'] ?? json['province_name'] ?? json['province'],
      ),
      cityName: _nullableString(
        json['cityName'] ?? json['city_name'] ?? json['kota'],
      ),
      districtName: _nullableString(
        json['districtName'] ?? json['district_name'] ?? json['district'],
      ),
      isMain: _boolValue(
        json['isMain'] ??
            json['isPrimary'] ??
            json['is_primary'] ??
            json['isUtama'],
      ),
      latitude: _doubleValue(json['latitude'] ?? json['lat']),
      longitude: _doubleValue(json['longitude'] ?? json['lng']),
      pinpointAddress: _nullableString(
        json['pinpointAddress'] ?? json['pinpoint_address'],
      ),
      streetName: _nullableString(json['streetName'] ?? json['street_name']),
    );
  }

  factory MemberAddress.fromApiJson(Map<String, dynamic> json) =>
      MemberAddress.fromJson(json);

  /// Alias `isMain` — beberapa code pakai `isPrimary` literal.
  bool get isPrimary => isMain;

  Map<String, dynamic> toApiJson() {
    return {
      'label': label,
      'recipient': recipient,
      'phone': phone,
      'address': address,
      'city': city ?? cityName,
      'postalCode': postalCode,
      'areaId': areaId,
      'areaLabel': areaLabel,
      'provinceName': provinceName,
      'districtName': districtName,
      'isMain': isMain,
      'isPrimary': isMain,
      'latitude': latitude,
      'longitude': longitude,
      'pinpointAddress': pinpointAddress,
      'streetName': streetName,
    };
  }
}

String _firstString(Object? first,
    [Object? second, Object? third, Object? fourth]) {
  for (final value in [first, second, third, fourth]) {
    final text = _nullableString(value);
    if (text != null) return text;
  }
  return '';
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'ya';
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}
