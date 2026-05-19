import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/member_profile.dart';
import '../state/member_store.dart';

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
      final uri = ApiConfig.uri('/api/orders');
      final res = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final list = body is List
          ? body
          : (body is Map ? body['orders'] ?? body['data'] : null);
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(OrderSummary.fromJson)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchOrders] $e');
      return const [];
    }
  }

  Future<List<MemberAddress>> fetchAddresses() async {
    try {
      final uri = ApiConfig.uri('/api/member/addresses');
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
          .whereType<Map<String, dynamic>>()
          .map(MemberAddress.fromJson)
          .toList();
      memberStore.setAddresses(addresses);
      return addresses;
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchAddresses] $e');
      return const [];
    }
  }
}

final MemberService memberService = MemberService._();
