/// Member profile + order summary models.
///
/// MemberProfile = subset User dari Prisma (id, name, phone, email, role,
/// birthDate) yang relevant ke client. Tidak ada passwordHash / tokenVersion.
///
/// OrderSummary = subset Order untuk list di /member/orders. Kalau butuh
/// detail full (items, address, dst), fetch ulang via orderService.

import 'product.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'role': role,
        if (birthDate != null) 'birthDate': birthDate!.toIso8601String(),
      };
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
  final String paymentStatus;
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
    this.customerName = '',
    this.customerPhone = '',
    this.shippingAddress = '',
    this.shippingCity,
    this.orderType = 'DELIVERY',
    this.shippingMethod,
    this.courierCode,
    this.courierService,
    this.trackingNumber,
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
      id: json['id'] as String,
      orderNumber: json['orderNumber'] as String,
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      shippingAddress: json['shippingAddress'] as String? ?? '',
      shippingCity: json['shippingCity'] as String?,
      orderType: json['orderType'] as String? ?? 'DELIVERY',
      shippingMethod: json['shippingMethod'] as String?,
      courierCode: json['courierCode'] as String?,
      courierService: json['courierService'] as String?,
      trackingNumber: json['trackingNumber'] as String?,
      trackingToken: json['trackingToken'] as String?,
      biteshipTrackingUrl: json['biteshipTrackingUrl'] as String?,
      shipmentStatus: json['shipmentStatus'] as String?,
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      shippingCost: (json['shippingCost'] as num?)?.toInt() ?? 0,
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      uniqueCode: (json['uniqueCode'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'PENDING',
      paymentProvider: json['paymentProvider'] as String? ?? 'MANUAL',
      paymentStatus: json['paymentStatus'] as String? ?? 'UNPAID',
      paymentUrl: json['paymentUrl'] as String?,
      paymentProofUrl: json['paymentProofUrl'] as String?,
      manualBank: json['manualBank'] as String?,
      voucherCode: json['voucherCode'] as String?,
      items: (json['items'] as List?)
              ?.map((e) => OrderItemSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
    );
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
