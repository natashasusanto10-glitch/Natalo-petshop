import 'api_client.dart';

/// Layanan pencarian alamat sedang tidak bisa dipakai (billing Google
/// mati, kuota habis, API ditolak). SENGAJA dibedakan dari "tidak ada
/// hasil" — lihat catatan di [PlacesService.autocomplete].
class PlacesUnavailableException implements Exception {
  final String message;
  const PlacesUnavailableException(this.message);
  @override
  String toString() => message;
}

/// Place autocomplete suggestion (mis. "Jl. MT. Haryono No. 103, Medan").
class PlaceSuggestion {
  final String placeId;
  final String description;
  final String? mainText;
  final String? secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    this.mainText,
    this.secondaryText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      placeId: (json['placeId'] ?? json['place_id'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      mainText: json['mainText']?.toString() ??
          (json['structured_formatting'] is Map
              ? json['structured_formatting']['main_text']?.toString()
              : null),
      secondaryText: json['secondaryText']?.toString() ??
          (json['structured_formatting'] is Map
              ? json['structured_formatting']['secondary_text']?.toString()
              : null),
    );
  }
}

/// Detail place dengan koordinat (untuk pinpoint di address picker).
class PlaceDetails {
  final String placeId;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final String? postalCode;
  final String? city;
  final String? district;
  final String? province;

  const PlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    this.latitude,
    this.longitude,
    this.postalCode,
    this.city,
    this.district,
    this.province,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final address = _asMap(json['address']);
    final result = _asMap(json['result']);
    final geometry = _asMap(json['geometry']) ?? _asMap(result?['geometry']);
    final loc = _asMap(json['location']) ?? _asMap(geometry?['location']);
    final latRaw = loc?['lat'];
    final lngRaw = loc?['lng'];
    return PlaceDetails(
      placeId: _firstString([
        json['placeId'],
        json['place_id'],
        result?['place_id'],
      ]),
      formattedAddress: _firstString([
        json['formattedAddress'],
        json['formatted_address'],
        address?['formattedAddress'],
        address?['formatted_address'],
        result?['formatted_address'],
        address?['jalan'],
      ]),
      latitude: _toDouble([
        json['lat'],
        json['latitude'],
        address?['lat'],
        address?['latitude'],
        latRaw,
      ]),
      longitude: _toDouble([
        json['lng'],
        json['longitude'],
        address?['lng'],
        address?['longitude'],
        lngRaw,
      ]),
      postalCode: _nullableString([
        json['postalCode'],
        json['postal_code'],
        address?['postalCode'],
        address?['postal_code'],
        address?['kodePos'],
      ]),
      city: _nullableString([
        json['city'],
        json['kota'],
        address?['city'],
        address?['kota'],
      ]),
      district: _nullableString([
        json['district'],
        json['kecamatan'],
        address?['district'],
        address?['kecamatan'],
      ]),
      province: _nullableString([
        json['province'],
        json['provinsi'],
        address?['province'],
        address?['provinsi'],
      ]),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String _firstString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static String? _nullableString(List<dynamic> values) {
    final text = _firstString(values);
    return text.isEmpty ? null : text;
  }

  static double? _toDouble(List<dynamic> values) {
    for (final value in values) {
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }
}

/// Wrapper untuk Google Places API via Capacitor backend.
/// Match endpoint PWA:
/// - POST /api/places/autocomplete
/// - POST /api/places/details
/// - POST /api/places/reverse-geocode
///
/// Server-side proxy supaya API key Google tidak exposed di client.
class PlacesService {
  /// Autocomplete query → list suggestion. Dipakai di address picker.
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    String? sessionToken,
    double? lat,
    double? lng,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    try {
      final data = await apiClient.postJson(
        '/api/places/autocomplete',
        body: {
          'input': trimmed,
          'query': trimmed,
          if (sessionToken != null) 'sessionToken': sessionToken,
          if (lat != null && lng != null) ...{
            'location': '$lat,$lng',
            'lat': lat,
            'lng': lng,
          },
        },
      );
      final raw = data is Map
          ? (data['predictions'] ?? data['suggestions'] ?? data['items'])
          : data;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) =>
              PlaceSuggestion.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on ApiException catch (e) {
      // JANGAN kembalikan daftar kosong di sini. Dulu `catch (_) => []`
      // membuat layanan MATI tampil identik dengan "alamat tidak
      // ditemukan" — terbukti di produksi 2026-08-27: billing Google
      // nonaktif, pencarian alamat mati total, pengguna hanya melihat
      // kotak kosong dan mengira alamatnya yang tidak terdaftar.
      //
      // Backend kini mengirim 503/502 dengan pesan siap-tampil
      // (lib/places/google-status.ts); dilempar supaya widget bisa
      // membedakan gagal dari nihil.
      throw PlacesUnavailableException(
        e.message.isNotEmpty
            ? e.message
            : 'Pencarian alamat sedang bermasalah. Isi alamat secara manual.',
      );
    }
  }

  /// Detail place by placeId — return koordinat + komponen alamat lengkap.
  Future<PlaceDetails?> details({
    required String placeId,
    String? sessionToken,
  }) async {
    if (placeId.isEmpty) return null;
    try {
      final data = await apiClient.postJson(
        '/api/places/details',
        body: {
          'placeId': placeId,
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );
      if (data is! Map) return null;
      return PlaceDetails.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// Reverse geocode lat/lng → alamat. Dipakai saat user pakai "Lokasi Saya"
  /// di address picker → auto-fill address dari GPS.
  Future<PlaceDetails?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final data = await apiClient.postJson(
        '/api/places/reverse-geocode',
        body: {'lat': latitude, 'lng': longitude},
      );
      if (data is! Map) return null;
      return PlaceDetails.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }
}

final placesService = PlacesService();
