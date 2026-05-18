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
  final String? email;
  final String? phone;
  final String role;
  final DateTime? birthDate;

  const MemberProfile({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role = 'CUSTOMER',
    this.birthDate,
  });

  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    return MemberProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'CUSTOMER',
      birthDate: _parseDate(json['birthDate']),
    );
  }

  /// Alias `fromJson` — beberapa code (auth_service) pakai `fromApiJson`
  /// karena API response wrapped di `{user: {...}}`. Auto-unwrap kalau ada.
  factory MemberProfile.fromApiJson(Map<String, dynamic> json) {
    final raw = (json['user'] ?? json['data'] ?? json) as Map<String, dynamic>;
    return MemberProfile.fromJson(raw);
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
  final String id;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String shippingAddress;
  final String? shippingCity;
  final String orderType;
  final String? shippingMethod;
  final String? courierCode;
  final String? courierService;
  final String? trackingNumber;
  final String? trackingToken;
  final String? biteshipTrackingUrl;
  final String? shipmentStatus;
  final int subtotal;
  final int shippingCost;
  final int discount;
  final int total;
  final int? uniqueCode;
  final String status;
  final String paymentProvider;
  final String shippingMethod;
  final String orderType;
  final String? pickupCode;
  final String? pickupLocationId;
  final String? pickupLocationName;
  final String? pickupAddress;
  final String? pickupHours;
  final String? pickupMapsUrl;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String? paymentUrl;
  final String? paymentProofUrl;
  final String? manualBank;
  final String? voucherCode;
  final List<OrderItemSummary> items;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    this.paymentProvider = 'MANUAL',
    this.shippingMethod = 'DELIVERY',
    this.orderType = 'DELIVERY',
    this.pickupCode,
    this.pickupLocationId,
    this.pickupLocationName,
    this.pickupAddress,
    this.pickupHours,
    this.pickupMapsUrl,
    this.pickupLatitude,
    this.pickupLongitude,
    this.paymentUrl,
    this.paymentProofUrl,
    this.manualBank,
    this.uniqueCode,
    this.trackingToken,
    this.biteshipTrackingUrl,
    this.shipmentStatus,
    this.subtotal = 0,
    this.shippingCost = 0,
    this.discount = 0,
    required this.total,
    this.uniqueCode,
    required this.status,
    this.paymentProvider = 'MANUAL',
    required this.paymentStatus,
    this.paymentUrl,
    this.paymentProofUrl,
    this.manualBank,
    this.voucherCode,
    this.items = const [],
    required this.createdAt,
    this.updatedAt,
  });

  /// Jumlah produk unique (items.length) — beberapa screen pakai itemCount.
  int get itemCount =>
      items.fold(0, (sum, it) => sum + it.quantity);

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      orderNumber: (json['orderNumber'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      paymentStatus: (json['paymentStatus'] ?? 'UNPAID').toString(),
      paymentProvider: (json['paymentProvider'] ?? 'MANUAL').toString(),
      shippingMethod:
          (json['shippingMethod'] ?? json['shipping_method'] ?? 'DELIVERY')
              .toString(),
      orderType:
          (json['orderType'] ?? json['order_type'] ?? 'DELIVERY').toString(),
      pickupCode: (json['pickupCode'] ?? json['pickup_code'])?.toString(),
      pickupLocationId:
          (json['pickupLocationId'] ?? json['pickup_location_id'])?.toString(),
      pickupLocationName:
          (json['pickupLocationName'] ?? json['pickup_location_name'])
              ?.toString(),
      pickupAddress:
          (json['pickupAddress'] ?? json['pickup_address'])?.toString(),
      pickupHours: (json['pickupHours'] ?? json['pickup_hours'])?.toString(),
      pickupMapsUrl:
          (json['pickupMapsUrl'] ?? json['pickup_maps_url'])?.toString(),
      pickupLatitude: _asDoubleOrNull(
        json['pickupLatitude'] ?? json['pickup_latitude'],
      ),
      pickupLongitude: _asDoubleOrNull(
        json['pickupLongitude'] ?? json['pickup_longitude'],
      ),
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

  bool get isSelfPickup {
    final normalizedMethod = shippingMethod.toUpperCase();
    final normalizedType = orderType.toUpperCase();
    return normalizedMethod == 'SELF_PICKUP' ||
        normalizedMethod == 'SELF-PICKUP' ||
        normalizedMethod == 'PICKUP' ||
        normalizedType == 'SELF_PICKUP' ||
        normalizedType == 'PICKUP';
  }
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
        price: price,
        stock: 1, // unknown — assume available, server akan validate.
        weightGram: weightGram,
        imageUrl: imageUrl ?? '',
        category: categoryName ?? '',
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
      id: json['id'] as String,
      productId: (json['productId'] ?? productMap?['id']) as String? ?? '',
      productSlug: (productMap?['slug']) as String?,
      variantId: json['variantId'] as String?,
      variantLabel: json['variantLabel'] as String?,
      name: (json['name'] ?? productMap?['name']) as String? ?? '',
      imageUrl:
          (json['imageUrl'] ?? productMap?['imageUrl']) as String?,
      categoryName: (json['categoryName'] ??
          (productMap?['category'] is Map
              ? productMap!['category']['name']
              : productMap?['category'])) as String?,
      price: (json['price'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      weightGram: (json['weightGram'] as num?)?.toInt() ?? 500,
      reviewed: json['reviewed'] as bool? ?? false,
    );
  }
}

// ── helper ──
DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
