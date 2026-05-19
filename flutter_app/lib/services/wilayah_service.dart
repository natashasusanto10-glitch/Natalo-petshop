import 'api_client.dart';

/// Wilayah admin Indonesia — match endpoint PWA GET /api/wilayah/[...path].
/// Catchall pattern, segment di path → cascade:
///
/// - GET /api/wilayah/provinces → list provinsi
/// - GET /api/wilayah/provinces/{provinceId}/regencies → kabupaten/kota
/// - GET /api/wilayah/regencies/{regencyId}/districts → kecamatan
/// - GET /api/wilayah/districts/{districtId}/villages → desa/kelurahan
///
/// Data berasal dari wilayah.id (kemendagri) — dipakai untuk address picker
/// step-by-step (provinsi → kota → kec → desa → kode pos).
class WilayahRegion {
  final String id;
  final String name;
  final String? code; // BPS code

  const WilayahRegion({
    required this.id,
    required this.name,
    this.code,
  });

  factory WilayahRegion.fromJson(Map<String, dynamic> json) {
    return WilayahRegion(
      id: (json['id'] ?? json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      code: json['code']?.toString(),
    );
  }
}

class WilayahService {
  Future<List<WilayahRegion>> _fetch(String path) async {
    try {
      final data = await apiClient.getJson('/api/wilayah/$path');
      final raw = data is Map
          ? (data['items'] ?? data['data'] ?? data['regions'])
          : data;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
              (item) => WilayahRegion.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<WilayahRegion>> provinces() => _fetch('provinces');

  Future<List<WilayahRegion>> regencies(String provinceId) =>
      _fetch('provinces/${Uri.encodeComponent(provinceId)}/regencies');

  Future<List<WilayahRegion>> districts(String regencyId) =>
      _fetch('regencies/${Uri.encodeComponent(regencyId)}/districts');

  Future<List<WilayahRegion>> villages(String districtId) =>
      _fetch('districts/${Uri.encodeComponent(districtId)}/villages');
}

final wilayahService = WilayahService();
