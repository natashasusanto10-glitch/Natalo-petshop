/// Member profile + order summary models.
///
/// MemberProfile = subset User dari Prisma (id, name, phone, email, role,
/// birthDate) yang relevant ke client. Tidak ada passwordHash / tokenVersion.
///
/// OrderSummary = subset Order untuk list di /member/orders. Kalau butuh
/// detail full (items, address, dst), fetch ulang via orderService.

import 'product.dart';

// Re-export sister models — beberapa code lain import `member_profile.dart`
// dan expect MemberAddress + MemberVoucher juga tersedia dari sana.
export 'member_address.dart';
export 'member_voucher.dart';

class MemberProfile {
  final String id;
  final String name;
  /// Public handle (IG/TikTok-style). 3-30 char, lowercase alfanum +
  /// `_` + `.`. Nullable buat user existing yang belum set — UI
  /// fallback ke `name` di feed/komentar, plus banner prompt di home.
  final String? username;
  final String? email;
  final String? phone;
  final String role;
  final DateTime? birthDate;
  final DateTime? createdAt;
  final int points;
  final String? profilePhotoUrl;
  /// Bio user — short description max 150 char yang muncul di header
  /// profile screen. Nullable / empty → tampilkan placeholder
  /// "Tambahkan bio" di edit form.
  final String? bio;

  const MemberProfile({
    required this.id,
    required this.name,
    this.username,
    this.email,
    this.phone,
    this.role = 'CUSTOMER',
    this.birthDate,
    this.createdAt,
    this.points = 0,
    this.profilePhotoUrl,
    this.bio,
  });

  bool get isAdmin => role.toUpperCase() == 'ADMIN';
  String get initial =>
      name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();
  DateTime get memberSince => createdAt ?? DateTime.now();

  /// Display handle untuk feed/komentar/profile. `@username` kalau set,
  /// fallback `name` kalau user belum set username. Konsisten di semua
  /// surface yang public-social.
  String get displayHandle =>
      (username != null && username!.isNotEmpty) ? '@$username' : name;

  bool get hasUsername => username != null && username!.isNotEmpty;

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    return MemberProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      username: _nullableString(json['username']),
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'CUSTOMER',
      birthDate: _parseDate(json['birthDate']),
      createdAt: _parseDate(json['createdAt'] ?? json['memberSince']),
      points: _asInt(json['points'] ?? json['loyaltyPoints']),
      profilePhotoUrl: _nullableString(
        json['profilePhotoUrl'] ??
            json['profile_photo_url'] ??
            json['avatarUrl'] ??
            json['photoUrl'] ??
            json['imageUrl'],
      ),
      bio: _nullableString(json['bio']),
    );
  }

  /// Alias `fromJson` — beberapa code (auth_service) pakai `fromApiJson`
  /// karena API response wrapped di `{user: {...}}`. Auto-unwrap kalau ada.
  factory MemberProfile.fromApiJson(Map<String, dynamic> json) {
    final raw = (json['user'] ?? json['data'] ?? json) as Map<String, dynamic>;
    return MemberProfile.fromJson(raw);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'email': email,
        'phone': phone,
        'role': role,
        'birthDate': birthDate?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'points': points,
        'profilePhotoUrl': profilePhotoUrl,
        'bio': bio,
      };

  MemberProfile copyWith({
    String? name,
    String? username,
    bool clearUsername = false,
    String? email,
    String? phone,
    String? role,
    DateTime? birthDate,
    DateTime? createdAt,
    int? points,
    String? profilePhotoUrl,
    bool clearProfilePhoto = false,
    String? bio,
    bool clearBio = false,
  }) {
    return MemberProfile(
      id: id,
      name: name ?? this.name,
      username: clearUsername ? null : username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      points: points ?? this.points,
      profilePhotoUrl:
          clearProfilePhoto ? null : profilePhotoUrl ?? this.profilePhotoUrl,
      bio: clearBio ? null : bio ?? this.bio,
    );
  }
}

class MemberVoucher {
  final String code;
  final String title;
  final String description;
  final DateTime expiresAt;
  final String type;
  final String visibility;
  final String discountScope;

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
    this.type = 'PUBLIC_PRODUCT_DISCOUNT',
    this.visibility = 'PUBLIC',
    this.discountScope = 'PRODUCT',
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
    final type = (json['type'] ?? '').toString().toUpperCase();
    final sourceType = (json['sourceType'] ?? json['source_type'] ?? '')
        .toString()
        .toUpperCase();
    final userId = (json['userId'] ?? json['user_id'])?.toString();
    final normalizedType = type.isNotEmpty
        ? type
        : sourceType == 'SELLER_MANUAL'
            ? 'PRIVATE_MANUAL_CODE'
            : userId != null && userId.isNotEmpty
                ? 'LOYALTY_POINT_CLAIM'
                : 'PUBLIC_PRODUCT_DISCOUNT';
    final visibility = (json['visibility'] ?? '').toString().toUpperCase();
    final normalizedVisibility = visibility.isNotEmpty
        ? visibility
        : normalizedType == 'PRIVATE_MANUAL_CODE'
            ? 'PRIVATE'
            : normalizedType == 'LOYALTY_POINT_CLAIM'
                ? 'USER_OWNED'
                : 'PUBLIC';
    final scope = (json['discountScope'] ?? json['discount_scope'] ?? '')
        .toString()
        .toUpperCase();

    return MemberVoucher(
      code: (json['code'] ?? '').toString(),
      title: title,
      description: (json['description'] ??
              (minimum > 0 ? 'Minimal belanja Rp$minimum.' : 'Voucher aktif.'))
          .toString(),
      expiresAt: expires ?? DateTime.now().add(const Duration(days: 30)),
      type: normalizedType,
      visibility: normalizedVisibility,
      discountScope: scope.isNotEmpty
          ? scope
          : normalizedType == 'PUBLIC_FREE_SHIPPING'
              ? 'SHIPPING'
              : 'PRODUCT',
      discount: discount,
      minimumOrder: minimum,
      applicable: applicable,
      disabledReason: disabledReason?.isEmpty == true ? null : disabledReason,
    );
  }

  bool get isFreeShipping => type == 'PUBLIC_FREE_SHIPPING';
  bool get isProductDiscount => type == 'PUBLIC_PRODUCT_DISCOUNT';
  bool get isLoyaltyClaim => type == 'LOYALTY_POINT_CLAIM';
  bool get isPrivateManual => type == 'PRIVATE_MANUAL_CODE';
  bool get isShippingDiscount => discountScope == 'SHIPPING';
  bool get isProductScope => discountScope != 'SHIPPING';
}

class OrderSummary {
  // ── Identifiers ──
  final String id;
  final String orderNumber;

  // ── Customer + shipping address (kalau ada) ──
  final String customerName;
  final String customerPhone;
  final String shippingAddress;
  final String? shippingCity;

  // ── Order type + shipping ──
  final String orderType; // DELIVERY / SELF_PICKUP
  final String shippingMethod; // DELIVERY / SELF_PICKUP / dst
  final String? courierCode;
  final String? courierService;
  final String? trackingNumber;
  final String? trackingToken;
  final String? biteshipTrackingUrl;
  final String? shipmentStatus;

  // ── Pickup info (kalau SELF_PICKUP) ──
  final String? pickupCode;
  final String? pickupLocationId;
  final String? pickupLocationName;
  final String? pickupAddress;
  final String? pickupHours;
  final String? pickupMapsUrl;
  final double? pickupLatitude;
  final double? pickupLongitude;

  // ── Pricing (semua dalam Rupiah) ──
  final double subtotal;
  final double shippingCost;
  final double discount;
  final double total;
  final int? uniqueCode;

  // ── Status + payment ──
  final String status; // PENDING/PAID/PROCESSING/SHIPPED/DELIVERED/CANCELLED
  final String paymentStatus; // UNPAID/PENDING/PAID/FAILED
  final String paymentProvider; // MANUAL/MIDTRANS
  final String? paymentUrl;
  final String? paymentProofUrl;
  final String? manualBank;
  final String? voucherCode;

  // ── Items + timestamps ──
  final List<OrderItemSummary> items;

  /// Pre-computed item count dari API — dipakai kalau items[] belum di-load
  /// (mis. list endpoint return ringkas). Fallback ke `items.fold(quantity)`.
  final int itemCountFromApi;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deliveredAt;
  final DateTime? completedAt;
  final DateTime? statusUpdatedAt;

  /// Detail URL — direct link ke /pesanan/[orderNumber] di web.
  final String? detailUrl;

  const OrderSummary({
    required this.id,
    required this.orderNumber,
    this.customerName = '',
    this.customerPhone = '',
    this.shippingAddress = '',
    this.shippingCity,
    this.orderType = 'DELIVERY',
    this.shippingMethod = 'DELIVERY',
    this.courierCode,
    this.courierService,
    this.trackingNumber,
    this.trackingToken,
    this.biteshipTrackingUrl,
    this.shipmentStatus,
    this.pickupCode,
    this.pickupLocationId,
    this.pickupLocationName,
    this.pickupAddress,
    this.pickupHours,
    this.pickupMapsUrl,
    this.pickupLatitude,
    this.pickupLongitude,
    this.subtotal = 0,
    this.shippingCost = 0,
    this.discount = 0,
    this.total = 0,
    this.uniqueCode,
    required this.status,
    required this.paymentStatus,
    this.paymentProvider = 'MANUAL',
    this.paymentUrl,
    this.paymentProofUrl,
    this.manualBank,
    this.voucherCode,
    this.items = const [],
    this.itemCountFromApi = 0,
    required this.createdAt,
    this.updatedAt,
    this.deliveredAt,
    this.completedAt,
    this.statusUpdatedAt,
    this.detailUrl,
  });

  /// Jumlah unit produk (sum quantities). Pakai `itemCountFromApi` kalau
  /// items[] kosong tapi server kasih count (list endpoint compact).
  int get itemCount {
    if (items.isNotEmpty) {
      return items.fold<int>(0, (sum, it) => sum + it.quantity);
    }
    return itemCountFromApi;
  }

  bool get isSelfPickup {
    final m = shippingMethod.toUpperCase();
    final t = orderType.toUpperCase();
    return m == 'SELF_PICKUP' ||
        m == 'SELF-PICKUP' ||
        m == 'PICKUP' ||
        t == 'SELF_PICKUP' ||
        t == 'PICKUP';
  }

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    final orderItems = itemsJson is List
        ? itemsJson
            .whereType<Map<String, dynamic>>()
            .map(OrderItemSummary.fromJson)
            .toList()
        : const <OrderItemSummary>[];

    return OrderSummary(
      id: (json['id'] ?? json['orderNumber'] ?? '').toString(),
      orderNumber: (json['orderNumber'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      customerPhone: (json['customerPhone'] ?? '').toString(),
      shippingAddress: (json['shippingAddress'] ?? '').toString(),
      shippingCity: _nullableString(json['shippingCity']),
      status: (json['status'] ?? 'PENDING').toString(),
      paymentStatus: (json['paymentStatus'] ?? 'UNPAID').toString(),
      paymentProvider: (json['paymentProvider'] ?? 'MANUAL').toString(),
      shippingMethod:
          (json['shippingMethod'] ?? json['shipping_method'] ?? 'DELIVERY')
              .toString(),
      orderType:
          (json['orderType'] ?? json['order_type'] ?? 'DELIVERY').toString(),
      courierCode: _nullableString(json['courierCode']),
      courierService: _nullableString(json['courierService']),
      trackingNumber: _nullableString(json['trackingNumber']),
      trackingToken: _nullableString(json['trackingToken']),
      biteshipTrackingUrl: _nullableString(json['biteshipTrackingUrl']),
      shipmentStatus: _nullableString(json['shipmentStatus']),
      pickupCode: _nullableString(json['pickupCode'] ?? json['pickup_code']),
      pickupLocationId: _nullableString(
        json['pickupLocationId'] ?? json['pickup_location_id'],
      ),
      pickupLocationName: _nullableString(
        json['pickupLocationName'] ??
            json['pickup_location_name'] ??
            json['pickupStoreName'] ??
            json['pickup_store_name'],
      ),
      pickupAddress: _nullableString(
        json['pickupAddress'] ??
            json['pickup_address'] ??
            json['pickupStoreAddress'] ??
            json['pickup_store_address'],
      ),
      pickupHours: _nullableString(json['pickupHours'] ?? json['pickup_hours']),
      pickupMapsUrl: _nullableString(
        json['pickupMapsUrl'] ?? json['pickup_maps_url'],
      ),
      pickupLatitude: _asDoubleOrNull(
        json['pickupLatitude'] ??
            json['pickup_latitude'] ??
            json['pickupStoreLatitude'] ??
            json['pickup_store_latitude'],
      ),
      pickupLongitude: _asDoubleOrNull(
        json['pickupLongitude'] ??
            json['pickup_longitude'] ??
            json['pickupStoreLongitude'] ??
            json['pickup_store_longitude'],
      ),
      paymentUrl: _nullableString(json['paymentUrl']),
      paymentProofUrl: _nullableString(json['paymentProofUrl']),
      manualBank: _nullableString(json['manualBank']),
      voucherCode: _nullableString(json['voucherCode']),
      uniqueCode:
          json['uniqueCode'] == null ? null : _asInt(json['uniqueCode']),
      detailUrl: _nullableString(json['detailUrl']),
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
      itemCountFromApi: _asInt(json['itemCount']),
      subtotal: _asDouble(json['subtotal']),
      shippingCost: _asDouble(json['shippingCost']),
      discount: _asDouble(json['discount']),
      total: _asDouble(json['total']),
      items: orderItems,
    );
  }

  /// Alias `fromJson` — beberapa code (service) pakai fromApiJson.
  factory OrderSummary.fromApiJson(Map<String, dynamic> json) =>
      OrderSummary.fromJson(json);
}

class OrderItemSummary {
  final String id;
  final String productId;
  final String? productSlug;
  final String? variantId;
  final String? variantLabel;
  final String name;
  final String? imageUrl;
  final String? categoryName;
  final int price;
  final int quantity;
  final int weightGram;

  /// True kalau user sudah submit review untuk OrderItem ini (status APPROVED
  /// atau PENDING). Dipakai untuk hide tombol "Ulas" di order detail.
  final bool reviewed;

  /// Reconstruct Product subset dari data yang available di order item.
  /// Cukup untuk pass ke cartStore.addProduct() saat reorder.
  Product get product => Product(
        id: productId,
        title: name,
        slug: productSlug ?? '',
        description: '',
        price: price.toDouble(),
        stock: 1, // unknown — assume available, server akan validate.
        weightGram: weightGram,
        imageUrl: imageUrl ?? '',
        category: categoryName ?? '',
        brand: '',
        rating: 0,
        reviewCount: 0,
      );

  const OrderItemSummary({
    required this.id,
    required this.productId,
    this.productSlug,
    this.variantId,
    this.variantLabel,
    required this.name,
    this.imageUrl,
    this.categoryName,
    required this.price,
    required this.quantity,
    this.weightGram = 500,
    this.reviewed = false,
  });

  factory OrderItemSummary.fromJson(Map<String, dynamic> json) {
    final productMap = json['product'] is Map<String, dynamic>
        ? json['product'] as Map<String, dynamic>
        : null;
    return OrderItemSummary(
      id: (json['id'] ?? json['productId'] ?? productMap?['id'] ?? '')
          .toString(),
      productId: (json['productId'] ?? productMap?['id'] ?? '').toString(),
      productSlug: _nullableString(json['productSlug'] ?? productMap?['slug']),
      variantId: _nullableString(json['variantId']),
      variantLabel: _nullableString(json['variantLabel']),
      name: (json['name'] ?? productMap?['name'] ?? '').toString(),
      imageUrl: _nullableString(
        json['imageUrl'] ?? json['productImage'] ?? productMap?['imageUrl'],
      ),
      categoryName: _nullableString(
        json['categoryName'] ??
            (productMap?['category'] is Map
                ? productMap!['category']['name']
                : productMap?['category']),
      ),
      price: (json['price'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      weightGram: (json['weightGram'] as num?)?.toInt() ?? 500,
      reviewed: json['reviewed'] as bool? ?? false,
    );
  }
}

// ── helpers ──
int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? _asDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _asDateTimeOrNull(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

String? _nullableString(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
