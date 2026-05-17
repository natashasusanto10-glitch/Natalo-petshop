import '../config/api_config.dart';

class MemberProfile {
  final String name;
  final String email;
  final String phone;
  final DateTime memberSince;
  final int points;
  final String? profilePhotoUrl;

  const MemberProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.memberSince,
    required this.points,
    this.profilePhotoUrl,
  });

  factory MemberProfile.fromApiJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse((json['createdAt'] ?? '').toString());
    return MemberProfile(
      name: (json['name'] ?? 'Member Natalo').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      memberSince: createdAt ?? DateTime.now(),
      points: _asInt(json['points']),
      profilePhotoUrl: _nullableString(
        json['profilePhotoUrl'] ??
            json['profile_photo_url'] ??
            json['avatarUrl'] ??
            json['photoUrl'] ??
            json['imageUrl'],
      ),
    );
  }

  MemberProfile copyWith({
    String? name,
    String? email,
    String? phone,
    DateTime? memberSince,
    int? points,
    String? profilePhotoUrl,
    bool clearProfilePhoto = false,
  }) {
    return MemberProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      memberSince: memberSince ?? this.memberSince,
      points: points ?? this.points,
      profilePhotoUrl:
          clearProfilePhoto ? null : profilePhotoUrl ?? this.profilePhotoUrl,
    );
  }

  String get initial => name.isEmpty ? 'N' : name[0].toUpperCase();
}

class MemberAddress {
  final String id;
  final String label;
  final String recipient;
  final String phone;
  final String address;
  final bool isPrimary;
  final String? city;
  final String? postalCode;
  final String? areaId;
  final String? areaLabel;
  final String? provinceName;
  final String? districtName;
  final double? latitude;
  final double? longitude;
  final String? pinpointAddress;

  const MemberAddress({
    required this.id,
    required this.label,
    required this.recipient,
    required this.phone,
    required this.address,
    required this.isPrimary,
    this.city,
    this.postalCode,
    this.areaId,
    this.areaLabel,
    this.provinceName,
    this.districtName,
    this.latitude,
    this.longitude,
    this.pinpointAddress,
  });

  factory MemberAddress.fromApiJson(Map<String, dynamic> json) {
    return MemberAddress(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? 'Alamat').toString(),
      recipient: (json['recipient'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      isPrimary: json['isMain'] == true || json['isPrimary'] == true,
      city: json['city']?.toString() ?? json['cityName']?.toString(),
      postalCode: json['postalCode']?.toString(),
      areaId: json['areaId']?.toString(),
      areaLabel: json['areaLabel']?.toString(),
      provinceName: json['provinceName']?.toString(),
      districtName: json['districtName']?.toString(),
      latitude: _asDoubleOrNull(json['latitude']),
      longitude: _asDoubleOrNull(json['longitude']),
      pinpointAddress: json['pinpointAddress']?.toString(),
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'label': label,
      'recipient': recipient,
      'phone': phone,
      'address': address,
      'city': city,
      'postalCode': postalCode,
      'areaId': areaId,
      'areaLabel': areaLabel,
      'provinceName': provinceName,
      'districtName': districtName,
      'isMain': isPrimary,
      'latitude': latitude,
      'longitude': longitude,
      'pinpointAddress': pinpointAddress,
    };
  }
}

class MemberVoucher {
  final String code;
  final String title;
  final String description;
  final DateTime expiresAt;

  /// Discount aktual (Rupiah) untuk subtotal saat ini. 0 kalau tidak applicable.
  final int discount;

  /// Minimum order untuk voucher ini berlaku. 0 = tanpa minimum.
  final int minimumOrder;

  /// True kalau voucher bisa dipakai sekarang (subtotal cukup, belum expired,
  /// belum dipakai user). Match field `applicable` dari API /api/cart/vouchers.
  final bool applicable;

  /// Alasan voucher disabled (untuk display di list inelibible). null kalau applicable.
  final String? disabledReason;

  const MemberVoucher({
    required this.code,
    required this.title,
    required this.description,
    required this.expiresAt,
    this.discount = 0,
    this.minimumOrder = 0,
    this.applicable = true,
    this.disabledReason,
  });

  factory MemberVoucher.fromApiJson(Map<String, dynamic> json) {
    final percent = _asInt(json['discountPercent'] ?? json['discount_percent']);
    final amount = _asInt(json['discountAmount'] ?? json['discount_amount']);
    final discount = _asInt(json['discount'] ?? json['discountAmount']);
    final minimum = _asInt(json['minimumOrder'] ?? json['minimum_order']);
    final expires = DateTime.tryParse(
      (json['expiresAt'] ?? json['expires_at'] ?? '').toString(),
    );
    final apiTitle = _nullableString(json['title'] ?? json['name']);
    final title = apiTitle ??
        (percent > 0
            ? 'Diskon $percent%'
            : amount > 0
                ? 'Potongan Rp$amount'
                : discount > 0
                    ? 'Hemat Rp$discount'
                    : 'Voucher Member');
    final applicable = json['applicable'] != false;
    final disabledReason =
        (json['disabledReason'] ?? json['disabled_reason'] ?? json['reason'])
            ?.toString();

    return MemberVoucher(
      code: (json['code'] ?? '').toString(),
      title: title,
      description: (json['description'] ??
              (minimum > 0 ? 'Minimal belanja Rp$minimum.' : 'Voucher aktif.'))
          .toString(),
      expiresAt: expires ?? DateTime.now().add(const Duration(days: 30)),
      discount: discount,
      minimumOrder: minimum,
      applicable: applicable,
      disabledReason: disabledReason?.isEmpty == true ? null : disabledReason,
    );
  }
}

class OrderSummary {
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final String paymentProvider;
  final String? paymentUrl;
  final String? paymentProofUrl;
  final String? manualBank;
  final int? uniqueCode;
  final String? trackingToken;
  final String? detailUrl;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? completedAt;
  final DateTime? statusUpdatedAt;
  final DateTime? updatedAt;
  final int itemCount;
  final double subtotal;
  final double shippingCost;
  final double discount;
  final double total;
  final List<OrderItemSummary> items;

  const OrderSummary({
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    this.paymentProvider = 'MANUAL',
    this.paymentUrl,
    this.paymentProofUrl,
    this.manualBank,
    this.uniqueCode,
    this.trackingToken,
    this.detailUrl,
    required this.createdAt,
    this.deliveredAt,
    this.completedAt,
    this.statusUpdatedAt,
    this.updatedAt,
    required this.itemCount,
    this.subtotal = 0,
    this.shippingCost = 0,
    this.discount = 0,
    required this.total,
    this.items = const [],
  });

  factory OrderSummary.fromApiJson(Map<String, dynamic> json) {
    final items = json['items'];
    final fallbackItemCount = items is List
        ? items.fold<int>(
            0,
            (sum, item) {
              if (item is Map<String, dynamic>) {
                return sum + _asInt(item['quantity']);
              }
              return sum;
            },
          )
        : 0;

    final orderItems = items is List
        ? items
            .whereType<Map<String, dynamic>>()
            .map(OrderItemSummary.fromApiJson)
            .toList()
        : <OrderItemSummary>[];

    return OrderSummary(
      orderNumber: (json['orderNumber'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      paymentStatus: (json['paymentStatus'] ?? 'UNPAID').toString(),
      paymentProvider: (json['paymentProvider'] ?? 'MANUAL').toString(),
      paymentUrl: json['paymentUrl']?.toString(),
      paymentProofUrl: json['paymentProofUrl']?.toString(),
      manualBank: json['manualBank']?.toString(),
      uniqueCode:
          json['uniqueCode'] == null ? null : _asInt(json['uniqueCode']),
      trackingToken: json['trackingToken']?.toString(),
      detailUrl: json['detailUrl']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      deliveredAt:
          _asDateTimeOrNull(json['deliveredAt'] ?? json['delivered_at']),
      completedAt:
          _asDateTimeOrNull(json['completedAt'] ?? json['completed_at']),
      statusUpdatedAt: _asDateTimeOrNull(
        json['statusUpdatedAt'] ?? json['status_updated_at'],
      ),
      updatedAt: _asDateTimeOrNull(json['updatedAt'] ?? json['updated_at']),
      itemCount: _asInt(json['itemCount']) == 0
          ? fallbackItemCount
          : _asInt(json['itemCount']),
      subtotal: _asDouble(json['subtotal']),
      shippingCost: _asDouble(json['shippingCost']),
      discount: _asDouble(json['discount']),
      total: _asDouble(json['total']),
      items: orderItems,
    );
  }
}

class OrderItemSummary {
  final String id;
  final String productId;
  final String name;
  final String? variantLabel;
  final bool reviewed;
  final int quantity;
  final double price;
  final String imageUrl;
  final String categoryName;

  const OrderItemSummary({
    required this.id,
    required this.productId,
    required this.name,
    this.variantLabel,
    this.reviewed = false,
    required this.quantity,
    required this.price,
    required this.imageUrl,
    required this.categoryName,
  });

  factory OrderItemSummary.fromApiJson(Map<String, dynamic> json) {
    return OrderItemSummary(
      id: (json['id'] ?? '').toString(),
      productId: (json['productId'] ?? '').toString(),
      name: (json['name'] ?? 'Produk Natalo').toString(),
      variantLabel: json['variantLabel']?.toString(),
      reviewed: json['reviewed'] == true,
      quantity: _asInt(json['quantity']),
      price: _asDouble(json['price']),
      imageUrl: _normalizeImageUrl(
        (json['imageUrl'] ?? json['productImage'] ?? '').toString(),
      ),
      categoryName: (json['categoryName'] ?? 'Produk').toString(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _asDoubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _asDateTimeOrNull(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '');
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return _normalizeImageUrl(text);
}

String _normalizeImageUrl(String url) {
  if (url.isEmpty || url.startsWith('http') || url.startsWith('assets/')) {
    return url;
  }
  final asset = _localProductAsset(url);
  if (asset != null) return asset;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

String? _localProductAsset(String url) {
  final filename = url.split('/').last;
  const copiedProductFiles = {
    'angels-creamy-chicken.png',
    'angels-creamy-salmon.jpg',
    'angels-creamy-tuna.png',
  };
  if (!copiedProductFiles.contains(filename)) return null;
  return 'assets/products/$filename';
}
