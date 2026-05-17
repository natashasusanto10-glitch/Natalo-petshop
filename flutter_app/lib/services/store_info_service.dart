import 'api_client.dart';

/// Info toko Natalo — match endpoint PWA GET /api/store-info.
/// Berisi jam operasional, alamat, kontak CS, kebijakan refund snippet, dll.
/// Dipakai di Login screen footer + Settings → Tentang Natalo.
class StoreInfo {
  final String? name;
  final String? address;
  final String? phone;
  final String? whatsappNumber;
  final String? email;
  final String? operationalHours;
  final String? operationalHoursOnline;
  final String? operationalHoursDelivery;
  final bool isOpen;
  final String? closedReason;
  final Map<String, dynamic> raw;

  const StoreInfo({
    this.name,
    this.address,
    this.phone,
    this.whatsappNumber,
    this.email,
    this.operationalHours,
    this.operationalHoursOnline,
    this.operationalHoursDelivery,
    this.isOpen = true,
    this.closedReason,
    this.raw = const {},
  });

  factory StoreInfo.fromJson(Map<String, dynamic> json) {
    return StoreInfo(
      name: json['name']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      whatsappNumber: json['whatsappNumber']?.toString() ??
          json['whatsapp']?.toString(),
      email: json['email']?.toString(),
      operationalHours: json['operationalHours']?.toString() ??
          json['hours']?.toString(),
      operationalHoursOnline: json['operationalHoursOnline']?.toString(),
      operationalHoursDelivery: json['operationalHoursDelivery']?.toString(),
      isOpen: json['isOpen'] != false,
      closedReason: json['closedReason']?.toString(),
      raw: json,
    );
  }
}

class StoreInfoService {
  StoreInfo? _cached;
  DateTime? _cachedAt;
  static const _cacheTtl = Duration(minutes: 30);

  /// Fetch store info dengan in-memory cache 30 menit.
  /// Force refresh dengan `useCache: false`.
  Future<StoreInfo?> fetch({bool useCache = true}) async {
    if (useCache && _cached != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!) < _cacheTtl) {
        return _cached;
      }
    }
    try {
      final data = await apiClient.getJson('/api/store-info');
      _cached = StoreInfo.fromJson(data);
      _cachedAt = DateTime.now();
      return _cached;
    } catch (_) {
      return _cached; // return stale kalau gagal
    }
  }
}

final storeInfoService = StoreInfoService();
