import 'api_client.dart';

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
    final loc = json['location'] ?? json['geometry']?['location'];
    final latRaw = loc is Map ? loc['lat'] : null;
    final lngRaw = loc is Map ? loc['lng'] : null;
    return PlaceDetails(
      placeId: (json['placeId'] ?? json['place_id'] ?? '').toString(),
      formattedAddress:
          (json['formattedAddress'] ?? json['formatted_address'] ?? '')
              .toString(),
      latitude: latRaw is num ? latRaw.toDouble() : double.tryParse('$latRaw'),
      longitude: lngRaw is num ? lngRaw.toDouble() : double.tryParse('$lngRaw'),
      postalCode: json['postalCode']?.toString(),
      city: json['city']?.toString(),
      district: json['district']?.toString(),
      province: json['province']?.toString(),
    );
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
    if (query.trim().length < 3) return const [];
    try {
      final data = await apiClient.postJson(
        '/api/places/autocomplete',
        body: {
          'query': query.trim(),
          if (sessionToken != null) 'sessionToken': sessionToken,
          if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
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
    } catch (_) {
      return const [];
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
