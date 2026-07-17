import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/member_profile.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

/// Member API: profile, orders list, addresses, vouchers, loyalty points.
/// Stub implementation — pakai endpoint REST yang sudah ada di Next.js.
/// Auth via session token di header Authorization: Bearer ...
class MemberService {
  MemberService._();

  Map<String, String> get _authHeaders {
    final token = memberStore.sessionToken ?? apiClient.lastSessionToken;
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token != null) 'cookie': 'member_session=$token',
    };
  }

  /// Update profil member — PATCH /api/auth/me (atau /api/member/profile
  /// kalau backend pakai route lain). Field opsional — hanya yang
  /// non-null yang dikirim. Return profile baru kalau sukses, null
  /// kalau gagal (404/405/network), exception bubble up untuk validation
  /// errors.
  Future<MemberProfile?> updateProfile({
    String? name,
    String? email,
    String? phone,
    DateTime? birthDate,
    String? bio,
    bool clearBio = false,
  }) async {
    try {
      final uri = ApiConfig.uri('/api/auth/me');
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (birthDate != null) body['birthDate'] = birthDate.toIso8601String();
      // Bio: kalau clearBio → kirim explicit null untuk delete dari DB.
      // Kalau bio != null → kirim string (empty string treated as clear
      // di backend). Kalau cuma 'bio' tidak dimaksud di-update, skip.
      if (clearBio) {
        body['bio'] = null;
      } else if (bio != null) {
        body['bio'] = bio;
      }
      if (body.isEmpty) return memberStore.profile;
      final res = await http
          .patch(
            uri,
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            '[memberService.updateProfile] failed ${res.statusCode}: ${res.body}',
          );
        }
        return null;
      }
      final json = jsonDecode(res.body);
      if (json is Map<String, dynamic>) {
        final raw = json['user'] ?? json['data'] ?? json;
        if (raw is Map<String, dynamic>) {
          return MemberProfile.fromJson(raw);
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.updateProfile] $e');
      return null;
    }
  }

  /// Upload foto profil ke backend (UploadThing CDN) + auto-save URL ke
  /// User.profilePhotoUrl. Return updated MemberProfile dengan URL CDN —
  /// caller bisa langsung pakai sebagai source of truth.
  ///
  /// Endpoint: POST /api/auth/me/photo (multipart, field "file").
  /// Max 5 MB, format JPG/PNG/WebP.
  Future<MemberProfile?> uploadProfilePhoto(String filePath) async {
    readOnlyMode.assertWritable('profile_photo_upload');
    try {
      final data = await apiClient.postMultipartFile(
        '/api/auth/me/photo',
        fieldName: 'file',
        filePath: filePath,
        filename: 'avatar.jpg',
        contentType: filePath.toLowerCase().endsWith('.png')
            ? 'image/png'
            : filePath.toLowerCase().endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg',
      );
      if (data is Map<String, dynamic>) {
        final user = data['user'];
        if (user is Map<String, dynamic>) {
          return MemberProfile.fromJson(user);
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.uploadProfilePhoto] $e');
      rethrow;
    }
  }

  /// Hapus foto profil di backend — set profilePhotoUrl ke null.
  Future<void> deleteProfilePhoto() async {
    readOnlyMode.assertWritable('profile_photo_delete');
    try {
      await apiClient.deleteJson('/api/auth/me/photo');
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.deleteProfilePhoto] $e');
      rethrow;
    }
  }

  /// Cek availability username live (debounced di UI). Return:
  ///   - `available: true` → bebas
  ///   - `available: false` + `reason` → TAKEN | RESERVED |
  ///     INVALID_FORMAT | RESERVED_KEYWORD
  Future<UsernameAvailability> checkUsernameAvailable(String raw) async {
    try {
      final uri = ApiConfig.uri('/api/me/username/check')
          .replace(queryParameters: {'username': raw});
      final res = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const UsernameAvailability(
          available: false,
          reason: 'AUTH',
          message: 'Login dulu untuk cek username.',
        );
      }
      if (res.statusCode != 200) {
        return const UsernameAvailability(
          available: false,
          reason: 'NETWORK',
          message: 'Gagal cek username. Coba lagi.',
        );
      }
      final json = jsonDecode(res.body);
      if (json is Map<String, dynamic>) {
        return UsernameAvailability(
          available: json['available'] == true,
          reason: json['reason'] as String?,
          message: json['message'] as String?,
        );
      }
      return const UsernameAvailability(available: false, reason: 'NETWORK');
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.checkUsername] $e');
      return const UsernameAvailability(
        available: false,
        reason: 'NETWORK',
        message: 'Gagal cek username. Coba lagi.',
      );
    }
  }

  /// Ambil `nextAllowedAt` — kapan user boleh ganti username lagi
  /// (cooldown 30 hari), null kalau sudah boleh ganti sekarang.
  Future<DateTime?> fetchUsernameNextAllowedAt() async {
    try {
      final data = await apiClient.getJson('/api/me/username');
      if (data is Map<String, dynamic> && data['nextAllowedAt'] is String) {
        return DateTime.tryParse(data['nextAllowedAt'] as String);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[memberService.fetchUsernameNextAllowedAt] $e');
      }
      return null;
    }
  }

  /// Set / change username. Server validate + reserve 30 hari handle
  /// lama. Return updated username pada sukses, throw ApiException
  /// kalau gagal (caller display error.message).
  Future<String> setUsername(String username) async {
    readOnlyMode.assertWritable('username_set');
    try {
      final data = await apiClient.patchJson(
        '/api/me/username',
        body: {'username': username},
      );
      if (data is Map<String, dynamic> && data['username'] is String) {
        return data['username'] as String;
      }
      throw const ApiException('Format response username invalid');
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.setUsername] $e');
      rethrow;
    }
  }

  Future<MemberProfile?> fetchProfile() async {
    try {
      final uri = ApiConfig.uri('/api/auth/me');
      final res = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      // BUG FIX: bedakan 401 (session invalid — user.id tidak ada di DB,
      // mungkin admin switch DB / user dihapus / session token expired)
      // dari error lain (5xx, network glitch). 401 harus throw supaya
      // memberStore.hydrateFromApi tahu untuk force-clear cache + logout.
      // Sebelumnya: 401 dianggap sama dengan network glitch → return null
      // → memberStore tetap render user "logged in" walaupun server udah
      // bilang session invalid.
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const ApiException('session invalid', statusCode: 401);
      }
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final user = body['user'] ?? body['data'] ?? body;
        if (user is Map<String, dynamic>) return MemberProfile.fromJson(user);
      }
      return null;
    } on ApiException {
      rethrow; // bubble up untuk caller handle 401 secara explicit
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchProfile] $e');
      return null;
    }
  }

  Future<List<OrderSummary>> fetchOrders() async {
    try {
      // Endpoint backend untuk member orders list ada di
      // `/api/member/orders` (GET, return {orders: [...]}). Endpoint
      // `/api/orders` HANYA POST untuk checkout — tidak ada GET handler,
      // jadi sebelumnya request return 404/405 → service return empty
      // list → user lihat "Belum ada pesanan" padahal punya order
      // PENDING (Belum Bayar) di DB.
      final uri = ApiConfig.uri('/api/member/orders');
      final res = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final list = body is List
          ? body
          : (body is Map ? body['orders'] ?? body['data'] : null);
      if (list is! List) return const [];
      final orders = list
          .whereType<Map<String, dynamic>>()
          .map(OrderSummary.fromJson)
          .toList();
      memberStore.setOrders(orders);
      return orders;
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchOrders] $e');
      return const [];
    }
  }

  Future<List<MemberAddress>> fetchAddresses() async {
    try {
      // Web/Capacitor lama memakai endpoint canonical `/api/alamat`.
      // Jangan bergantung ke alias `/api/addresses`, karena APK production
      // bisa jalan terhadap backend yang belum punya re-export alias itu.
      final uri = ApiConfig.uri('/api/alamat');
      final res = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final list = body is List
          ? body
          : (body is Map ? body['addresses'] ?? body['data'] : null);
      if (list is! List) return const [];
      final addresses = list
          .whereType<Map>()
          .map(
              (item) => MemberAddress.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      memberStore.setAddresses(addresses);
      return addresses;
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchAddresses] $e');
      return const [];
    }
  }

  Future<MemberAddress> createAddress(MemberAddress address) async {
    readOnlyMode.assertWritable('address_create');
    final data = await apiClient.postJson(
      '/api/alamat',
      body: address.toApiJson(),
    );
    return _addressFromResponse(data);
  }

  Future<MemberAddress> updateAddress(MemberAddress address) async {
    readOnlyMode.assertWritable('address_update');
    final data = await apiClient.putJson(
      '/api/alamat/${Uri.encodeComponent(address.id)}',
      body: address.toApiJson(),
    );
    return _addressFromResponse(data);
  }

  Future<MemberAddress> setPrimaryAddress(String id) async {
    readOnlyMode.assertWritable('address_update');
    final data = await apiClient.postJson(
      '/api/alamat/${Uri.encodeComponent(id)}/set-primary',
      body: const {},
    );
    return _addressFromResponse(data);
  }

  Future<void> deleteAddress(String id) async {
    readOnlyMode.assertWritable('address_delete');
    await apiClient.deleteJson(
      '/api/alamat/${Uri.encodeComponent(id)}',
    );
  }

  MemberAddress _addressFromResponse(dynamic data) {
    final raw = data is Map ? (data['address'] ?? data['data'] ?? data) : null;
    if (raw is Map) {
      return MemberAddress.fromJson(Map<String, dynamic>.from(raw));
    }
    throw const ApiException('Response alamat tidak valid.');
  }

  /// Fetch SEMUA voucher relevan untuk user (publik admin + owned).
  ///
  /// Reroute ke `/api/cart/vouchers` — endpoint `/api/member/vouchers` lama
  /// di-deprecate karena duplicate logic + bug filter `userId` saja.
  /// Sekarang 1 source of truth di backend (`lib/voucher-list.ts`).
  ///
  /// Return combined list: applicable dulu, lalu unavailable. Caller bisa
  /// split via `.applicable` field kalau perlu render section terpisah.
  Future<List<MemberVoucher>> fetchVouchers() async {
    try {
      final productIds =
          cartStore.items.map((item) => item.productId).toSet().toList();
      final result =
          await fetchCartVouchers(cartStore.subtotal.round(), productIds);
      return [...result.available, ...result.unavailable];
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchVouchers] $e');
      return const [];
    }
  }

  Future<({List<MemberVoucher> available, List<MemberVoucher> unavailable})>
      fetchCartVouchers(int subtotal, List<String> productIds) async {
    try {
      final data = await apiClient.getJson(
        '/api/cart/vouchers',
        query: {'subtotal': '$subtotal', 'productIds': productIds.join(',')},
      );

      List<MemberVoucher> parse(Object? raw) {
        return _asList(raw)
            .whereType<Map<String, dynamic>>()
            .map(MemberVoucher.fromApiJson)
            .toList();
      }

      if (data is Map<String, dynamic>) {
        return (
          available: parse(data['available'] ?? data['eligible']),
          unavailable: parse(data['unavailable'] ?? data['ineligible']),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchCartVouchers] $e');
    }

    return (
      available: const <MemberVoucher>[],
      unavailable: const <MemberVoucher>[]
    );
  }

  Future<({String code, int discountAmount})> claimLoyaltyVoucher(
    int points,
  ) async {
    readOnlyMode.assertWritable('voucher_claim');
    final data = await apiClient.postJson(
      '/api/member/claim-voucher',
      body: {'points': points},
    );
    final amount = data is Map ? data['discountAmount'] : null;
    return (
      code: data is Map ? (data['code'] ?? '').toString() : '',
      discountAmount: amount is num
          ? amount.round()
          : int.tryParse(amount?.toString() ?? '') ?? 0,
    );
  }

  Future<List<LoyaltyHistoryEntry>> fetchLoyaltyHistory() async {
    try {
      final data = await apiClient.getJson('/api/member/loyalty/history');
      final raw = data is Map
          ? (data['entries'] ?? data['history'] ?? data['data'])
          : data;
      return _asList(raw)
          .whereType<Map<String, dynamic>>()
          .map(LoyaltyHistoryEntry.fromJson)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchLoyaltyHistory] $e');
      return const [];
    }
  }
}

final MemberService memberService = MemberService._();

List<dynamic> _asList(dynamic raw) => raw is List ? raw : const [];

class LoyaltyHistoryEntry {
  final String id;
  final int delta;
  final String source;
  final String description;
  final DateTime createdAt;

  const LoyaltyHistoryEntry({
    required this.id,
    required this.delta,
    required this.source,
    required this.description,
    required this.createdAt,
  });

  bool get isEarn => delta > 0;
  bool get isReviewBonus => source.startsWith('REVIEW:');

  factory LoyaltyHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'] ?? json['points'] ?? 0;
    final rawDate = json['createdAt'] ?? json['date'] ?? json['created_at'];
    final source = (json['source'] ?? '').toString();
    return LoyaltyHistoryEntry(
      id: (json['id'] ?? '').toString(),
      delta: rawDelta is num
          ? rawDelta.round()
          : int.tryParse(rawDelta.toString()) ?? 0,
      source: source,
      description: _loyaltyHistoryDescription(
        source: source,
        rawDescription: (json['description'] ?? json['note'] ?? '').toString(),
      ),
      createdAt: DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

String _loyaltyHistoryDescription({
  required String source,
  required String rawDescription,
}) {
  if (source.startsWith('REVIEW:') || rawDescription.startsWith('REVIEW:')) {
    return 'Bonus ulasan produk';
  }
  return rawDescription;
}

/// Hasil cek availability username dari /api/me/username/check.
/// reason values dari backend: TAKEN, RESERVED, INVALID_FORMAT,
/// RESERVED_KEYWORD. Local-only values: AUTH, NETWORK.
class UsernameAvailability {
  final bool available;
  final String? reason;
  final String? message;

  const UsernameAvailability({
    required this.available,
    this.reason,
    this.message,
  });

  bool get isTaken => reason == "TAKEN" || reason == "RESERVED";
  bool get isInvalidFormat =>
      reason == "INVALID_FORMAT" || reason == "RESERVED_KEYWORD";
}
