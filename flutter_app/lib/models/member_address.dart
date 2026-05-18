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
    this.isMain = false,
    this.latitude,
    this.longitude,
    this.pinpointAddress,
    this.streetName,
  });

  factory MemberAddress.fromJson(Map<String, dynamic> json) {
    return MemberAddress(
      id: json['id'] as String,
      label: json['label'] as String?,
      recipient: json['recipient'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String?,
      postalCode: json['postalCode'] as String?,
      areaId: json['areaId'] as String?,
      areaLabel: json['areaLabel'] as String?,
      provinceName: json['provinceName'] as String?,
      cityName: json['cityName'] as String?,
      districtName: json['districtName'] as String?,
      isMain: json['isMain'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      pinpointAddress: json['pinpointAddress'] as String?,
      streetName: json['streetName'] as String?,
    );
  }

  factory MemberAddress.fromApiJson(Map<String, dynamic> json) =>
      MemberAddress.fromJson(json);
}
