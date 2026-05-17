import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member_profile.dart';
import '../state/cart_store.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class MemberService {
  static const _profilePhotoPathKey = 'natalo_profile_photo_path';

  Future<MemberProfile> fetchProfile() async {
    final data = await apiClient.getJson('/api/member/profile');
    final user = data['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('Profil member tidak ditemukan.');
    }
    return _withLocalProfilePhoto(MemberProfile.fromApiJson(user));
  }

  Future<MemberProfile> updateProfile({
    required MemberProfile current,
    required String name,
    required String phone,
  }) async {
    readOnlyMode.assertWritable('profile_update');
    final data = await apiClient.putJson(
      '/api/member/profile',
      body: {
        'name': name,
        'phone': phone,
      },
    );
    final user = data['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('Response profil tidak valid.');
    }
    final updated =
        await _withLocalProfilePhoto(MemberProfile.fromApiJson(user));
    return current.copyWith(
      name: updated.name,
      email: updated.email,
      phone: updated.phone,
      profilePhotoUrl: updated.profilePhotoUrl,
    );
  }

  Future<MemberProfile> updateProfilePhoto({
    required MemberProfile current,
    required String sourcePath,
  }) async {
    readOnlyMode.assertWritable('profile_update');
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const ApiException('File foto tidak ditemukan.');
    }
    final directory = await getApplicationDocumentsDirectory();
    final extension = _fileExtension(sourcePath);
    final target = File(
      '${directory.path}${Platform.pathSeparator}natalo-profile-photo$extension',
    );
    if (target.existsSync()) {
      target.deleteSync();
    }
    final saved = source.copySync(target.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilePhotoPathKey, saved.path);
    return current.copyWith(profilePhotoUrl: saved.path);
  }

  Future<MemberProfile> deleteProfilePhoto(MemberProfile current) async {
    readOnlyMode.assertWritable('profile_update');
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_profilePhotoPathKey);
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    await prefs.remove(_profilePhotoPathKey);
    return current.copyWith(clearProfilePhoto: true);
  }

  Future<MemberProfile> _withLocalProfilePhoto(MemberProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final localPath = prefs.getString(_profilePhotoPathKey);
    if (localPath == null || localPath.isEmpty) return profile;
    if (!File(localPath).existsSync()) {
      await prefs.remove(_profilePhotoPathKey);
      return profile;
    }
    return profile.copyWith(profilePhotoUrl: localPath);
  }

  Future<List<MemberAddress>> fetchAddresses() async {
    final data = await apiClient.getJson('/api/addresses');
    final raw = data['addresses'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MemberAddress.fromApiJson)
        .toList();
  }

  Future<MemberAddress> createAddress(MemberAddress address) async {
    readOnlyMode.assertWritable('address_create');
    final data = await apiClient.postJson(
      '/api/addresses',
      body: address.toApiJson(),
    );
    final raw = data['address'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Response alamat tidak valid.');
    }
    return MemberAddress.fromApiJson(raw);
  }

  Future<MemberAddress> updateAddress(MemberAddress address) async {
    readOnlyMode.assertWritable('address_update');
    final data = await apiClient.putJson(
      '/api/addresses/${Uri.encodeComponent(address.id)}',
      body: address.toApiJson(),
    );
    final raw = data['address'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Response alamat tidak valid.');
    }
    return MemberAddress.fromApiJson(raw);
  }

  Future<MemberAddress> setPrimaryAddress(String id) async {
    readOnlyMode.assertWritable('address_update');
    final data = await apiClient.postJson(
      '/api/addresses/${Uri.encodeComponent(id)}/set-primary',
      body: const {},
    );
    final raw = data['address'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Response alamat tidak valid.');
    }
    return MemberAddress.fromApiJson(raw);
  }

  Future<void> deleteAddress(String id) async {
    readOnlyMode.assertWritable('address_delete');
    await apiClient.deleteJson('/api/addresses/${Uri.encodeComponent(id)}');
  }

  Future<List<MemberVoucher>> fetchVouchers() async {
    final data = await apiClient.getJson(
      '/api/member/vouchers',
      query: {'subtotal': '${cartStore.subtotal.round()}'},
    );
    final rawEligible = data['eligible'] ?? data['vouchers'];
    final rawIneligible = data['ineligible'];
    final vouchers = <MemberVoucher>[
      if (rawEligible is List)
        ...rawEligible
            .whereType<Map<String, dynamic>>()
            .map(MemberVoucher.fromApiJson),
      if (rawIneligible is List)
        ...rawIneligible
            .whereType<Map<String, dynamic>>()
            .map(MemberVoucher.fromApiJson),
    ];
    return vouchers;
  }

  /// Tukar poin loyalty jadi voucher belanja. Match endpoint PWA
  /// POST /api/member/claim-voucher dengan body `{points: 50|100|200}`.
  /// Return voucher code yang berhasil di-claim.
  ///
  /// Tier yang valid (sinkron dengan PWA TIERS constant):
  /// - 50 poin -> voucher Rp5.000
  /// - 100 poin -> voucher Rp10.000
  /// - 200 poin -> voucher Rp20.000
  ///
  /// Throw exception kalau poin tidak cukup atau tier invalid.
  Future<({String code, int discountAmount})> claimLoyaltyVoucher(
    int points,
  ) async {
    readOnlyMode.assertWritable('voucher_claim');
    final data = await apiClient.postJson(
      '/api/member/claim-voucher',
      body: {'points': points},
    );
    final amount = data['discountAmount'];
    return (
      code: (data['code'] ?? '').toString(),
      discountAmount: amount is num
          ? amount.round()
          : int.tryParse(amount?.toString() ?? '') ?? 0,
    );
  }

  /// Fetch riwayat transaksi loyalty point. Match endpoint PWA
  /// GET /api/member/loyalty/history.
  ///
  /// Return list of entries dengan delta points (+earn, -redeem), tanggal,
  /// dan description. Sorted desc by date (newest first).
  Future<List<LoyaltyHistoryEntry>> fetchLoyaltyHistory() async {
    try {
      final data = await apiClient.getJson('/api/member/loyalty/history');
      final raw = data['entries'] ?? data['history'] ?? data['data'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(LoyaltyHistoryEntry.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Match endpoint PWA GET /api/cart/vouchers?subtotal=N
  /// Return tuple: (available, unavailable). Available = bisa dipakai
  /// sekarang. Unavailable = visible tapi disabled (mis. subtotal kurang).
  ///
  /// Voucher SELLER_MANUAL TIDAK pernah muncul di sini (rahasia, harus
  /// di-validate via endpoint terpisah).
  Future<({List<MemberVoucher> available, List<MemberVoucher> unavailable})>
      fetchCartVouchers(int subtotal) async {
    final data = await apiClient.getJson(
      '/api/cart/vouchers',
      query: {'subtotal': '$subtotal'},
    );
    final rawAvailable = data['available'];
    final rawUnavailable = data['unavailable'];

    List<MemberVoucher> parse(Object? raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MemberVoucher.fromApiJson)
          .toList();
    }

    return (
      available: parse(rawAvailable),
      unavailable: parse(rawUnavailable),
    );
  }

  Future<List<OrderSummary>> fetchOrders() async {
    final data = await apiClient.getJson('/api/member/orders');
    final raw = data['orders'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OrderSummary.fromApiJson)
        .toList();
  }
}

final memberService = MemberService();

String _fileExtension(String path) {
  final filename = path.split(RegExp(r'[\\/]')).last;
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '.jpg';
  final ext = filename.substring(dot).toLowerCase();
  return ext.length > 6 ? '.jpg' : ext;
}

/// Entry di Riwayat Poin screen — 1 transaksi earn/redeem.
class LoyaltyHistoryEntry {
  final String id;

  /// Positive = earn (bonus belanja, promo). Negative = redeem (tukar voucher).
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
    final delta = rawDelta is num
        ? rawDelta.round()
        : int.tryParse(rawDelta.toString()) ?? 0;
    final rawDate = json['createdAt'] ?? json['date'] ?? json['created_at'];
    final createdAt = rawDate is String
        ? (DateTime.tryParse(rawDate) ?? DateTime.now())
        : DateTime.now();
    return LoyaltyHistoryEntry(
      id: (json['id'] ?? '').toString(),
      delta: delta,
      description: (json['description'] ?? json['note'] ?? '').toString(),
      createdAt: createdAt,
    );
  }
}
