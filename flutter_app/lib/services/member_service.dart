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
    final token = memberStore.sessionToken;
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
  }) async {
    try {
      final uri = ApiConfig.uri('/api/auth/me');
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (birthDate != null) body['birthDate'] = birthDate.toIso8601String();
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

  Future<MemberProfile?> fetchProfile() async {
    try {
      final uri = ApiConfig.uri('/api/auth/me');
      final res = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final user = body['user'] ?? body['data'] ?? body;
        if (user is Map<String, dynamic>) return MemberProfile.fromJson(user);
      }
      return null;
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

  Future<List<MemberVoucher>> fetchVouchers() async {
    try {
      final data = await apiClient.getJson(
        '/api/member/vouchers',
        query: {'subtotal': '${cartStore.subtotal.round()}'},
      );
      final list = <dynamic>[
        ..._asList(data is Map ? data['eligible'] : null),
        ..._asList(data is Map ? data['vouchers'] : null),
        ..._asList(data is Map ? data['ineligible'] : null),
        ..._asList(data is Map ? data['data'] : null),
      ];
      return list
          .whereType<Map<String, dynamic>>()
          .map(MemberVoucher.fromApiJson)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchVouchers] $e');
      return const [];
    }
  }

  Future<({List<MemberVoucher> available, List<MemberVoucher> unavailable})>
      fetchCartVouchers(int subtotal) async {
    try {
      final data = await apiClient.getJson(
        '/api/cart/vouchers',
        query: {'subtotal': '$subtotal'},
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
  final String description;
  final DateTime createdAt;

  const LoyaltyHistoryEntry({
    required this.id,
    required this.delta,
    required this.description,
    required this.createdAt,
  });

  bool get isEarn => delta > 0;

  factory LoyaltyHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'] ?? json['points'] ?? 0;
    final rawDate = json['createdAt'] ?? json['date'] ?? json['created_at'];
    return LoyaltyHistoryEntry(
      id: (json['id'] ?? '').toString(),
      delta: rawDelta is num
          ? rawDelta.round()
          : int.tryParse(rawDelta.toString()) ?? 0,
      description: (json['description'] ?? json['note'] ?? '').toString(),
      createdAt: DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
