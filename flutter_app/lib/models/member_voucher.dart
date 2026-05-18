/// Member voucher — match Prisma Voucher schema.
/// Stub minimal supaya voucher_service bisa compile.
class MemberVoucher {
  final String id;
  final String code;
  final String? description;
  final int? discountPercent;
  final int? discountAmount;
  final int minimumOrder;
  final int? maxUsage;
  final int usedCount;
  final String sourceType;
  final DateTime? expiresAt;
  final DateTime? validFrom;
  final bool isActive;

  const MemberVoucher({
    required this.id,
    required this.code,
    this.description,
    this.discountPercent,
    this.discountAmount,
    this.minimumOrder = 0,
    this.maxUsage,
    this.usedCount = 0,
    this.sourceType = 'CUSTOMER',
    this.expiresAt,
    this.validFrom,
    this.isActive = true,
  });

  bool get isPercentage => discountPercent != null && discountPercent! > 0;
  bool get isAmount => discountAmount != null && discountAmount! > 0;

  /// Hitung discount dari subtotal.
  int discountFor(int subtotal) {
    if (subtotal < minimumOrder) return 0;
    if (isPercentage) {
      return ((subtotal * discountPercent!) / 100).round();
    }
    if (isAmount) return discountAmount!;
    return 0;
  }

  factory MemberVoucher.fromJson(Map<String, dynamic> json) {
    return MemberVoucher(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      description: json['description'] as String?,
      discountPercent: (json['discountPercent'] as num?)?.toInt(),
      discountAmount: (json['discountAmount'] as num?)?.toInt(),
      minimumOrder: (json['minimumOrder'] as num?)?.toInt() ?? 0,
      maxUsage: (json['maxUsage'] as num?)?.toInt(),
      usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
      sourceType: json['sourceType'] as String? ?? 'CUSTOMER',
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      validFrom: DateTime.tryParse(json['validFrom']?.toString() ?? ''),
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  factory MemberVoucher.fromApiJson(Map<String, dynamic> json) =>
      MemberVoucher.fromJson(json);
}
