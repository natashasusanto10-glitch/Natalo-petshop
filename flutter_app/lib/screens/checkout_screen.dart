import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import '../services/app_analytics.dart';
import '../services/cart_service.dart';
import '../services/member_service.dart';
import '../services/order_service.dart';
import '../services/shipping_service.dart';
import '../services/voucher_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import 'order_success_screen.dart';

const _brandBlue = NataloColors.nataloBlue;
const _maxPricingSyncRetries = 3;
const _pricingSyncRetryDelays = [
  Duration(milliseconds: 800),
  Duration(milliseconds: 1500),
  Duration(milliseconds: 2500),
];

class CheckoutScreen extends StatefulWidget {
  /// Optional items override — kalau di-pass, checkout pakai item yang
  /// disediakan caller (mis. "Beli Sekarang" dari product detail). Kalau
  /// null, fallback ke `cartStore.items` (normal cart flow).
  final List<CartItem>? items;

  const CheckoutScreen({super.key, this.items});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _payment = 'Transfer Manual';
  bool _submitting = false;
  bool _redirectingToLogin = false;
  bool _loadingRates = true;
  String? _shippingMessage;
  List<MemberAddress> _addresses = memberStore.addresses;
  MemberAddress? _selectedAddress;
  List<ShippingRate> _shippingRates = const [ShippingRate.selfPickup];
  ShippingRate _selectedRate = ShippingRate.selfPickup;
  bool _shippingRateSelectedByUser = false;
  // Voucher state — server auto-applies best voucher; UI only shows summary
  // chips plus one manual-code field.
  MemberVoucher? _selectedFreeShippingVoucher;
  MemberVoucher? _selectedProductVoucher;
  MemberVoucher? _selectedLoyaltyVoucher;
  MemberVoucher? _selectedManualVoucher;
  List<MemberVoucher> _availableVouchers = const [];
  List<MemberVoucher> _unavailableVouchers = const [];
  bool _loadingVouchers = false;
  bool _syncingPricing = false;
  bool _voucherSyncFailed = false;
  bool _pricingRetryScheduled = false;
  int _pricingRetryAttempt = 0;
  String? _pricingSyncError;
  bool _autoVoucherSuppressed = false;
  // Saldo Refund toggle — default ON sesuai UX best practice (Tokopedia/
  // Shopee pattern: saldo refund available langsung dipakai). User bisa
  // toggle OFF kalau mau saving. Recompute pricing saat toggle change.
  bool _useRefundBalance = true;
  CheckoutRecalcResult? _checkoutPricing;
  bool _isNearBottom = false;
  // Catatan pesanan ke admin.
  final TextEditingController _noteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pricingRetryTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleCheckoutScroll);
    if (!memberStore.isLoggedIn) {
      _redirectingToLogin = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/member/login',
          arguments: {
            'redirect': '/checkout',
            if (widget.items != null) 'arguments': widget.items,
          },
        );
      });
      return;
    }
    _selectedAddress = _pickPrimaryAddress(_addresses);
    _loadCheckoutData();
  }

  MemberAddress? _pickPrimaryAddress(List<MemberAddress> addresses) {
    if (addresses.isEmpty) return null;
    return addresses.firstWhere(
      (address) => address.isPrimary,
      orElse: () => addresses.first,
    );
  }

  /// Items source — kalau widget.items di-pass (Buy Now), pakai itu.
  /// Otherwise default ke cartStore.items.
  List<CartItem> get _checkoutItems => widget.items ?? cartStore.items;

  /// BUGFIX(audit): bersihkan keranjang setelah order sukses TANPA menghapus
  /// item yang TIDAK di-order.
  /// - widget.items == null → full-cart checkout: semua item di cart memang
  ///   di-order → clear() seluruhnya (perilaku lama, benar).
  /// - widget.items != null → Buy Now / checkout sebagian: hapus HANYA item
  ///   yang benar-benar di-order (by key). remove() no-op untuk item Buy Now
  ///   yang memang tidak ada di cart. Sebelumnya clear() menghapus SELURUH
  ///   cart → item yang tidak dibeli ikut hilang (data loss).
  void _clearOrderedItemsFromCart() {
    final ordered = widget.items;
    if (ordered == null) {
      cartStore.clear();
      return;
    }
    for (final item in ordered) {
      cartStore.remove(item.key);
    }
  }

  /// Subtotal dari items (cartStore-aware atau override).
  double get _localItemsSubtotal => widget.items != null
      ? widget.items!.fold<double>(0, (sum, item) => sum + item.lineTotal)
      : cartStore.subtotal.toDouble();

  double get _itemsSubtotal =>
      _checkoutPricing?.subtotal.toDouble() ?? _localItemsSubtotal;

  double get _shippingCost =>
      _checkoutPricing?.shippingCost.toDouble() ??
      _selectedRate.price.toDouble();

  double get _voucherDiscount => _productDiscount + _shippingDiscount;

  double _checkoutRawNumber(Iterable<String> keys) {
    final raw = _checkoutPricing?.raw;
    if (raw == null) return 0;
    for (final key in keys) {
      final value = raw[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  double get _productDiscount {
    final explicit = _checkoutRawNumber(const [
      'productDiscount',
      'product_discount',
      'productDiscountAmount',
      'product_discount_amount',
    ]);
    if (explicit > 0) return explicit;
    return ((_selectedProductVoucher?.discount ?? 0) +
            (_selectedLoyaltyVoucher?.discount ?? 0) +
            (_selectedManualVoucher?.isProductScope == true
                ? _selectedManualVoucher!.discount
                : 0))
        .toDouble();
  }

  double get _shippingBaseCost {
    final explicit = _checkoutRawNumber(const [
      'originalShippingCost',
      'original_shipping_cost',
      'shippingBeforeDiscount',
      'shipping_before_discount',
      'shippingBaseCost',
      'shipping_base_cost',
    ]);
    if (explicit > 0) return explicit;
    if (_selectedRate.isSelfPickup) return 0;
    return _selectedRate.price.toDouble();
  }

  double get _shippingDiscount {
    if (_selectedRate.isSelfPickup) return 0;
    final explicit = _checkoutRawNumber(const [
      'shippingDiscount',
      'shipping_discount',
      'shippingDiscountAmount',
      'shipping_discount_amount',
      'shippingFeeDiscount',
      'shipping_fee_discount',
      'ongkirDiscount',
      'ongkir_discount',
    ]);
    if (explicit > 0) return explicit;
    if (_selectedFreeShippingVoucher != null) {
      return _selectedFreeShippingVoucher!.discount
          .clamp(0, _shippingBaseCost)
          .toDouble();
    }
    if (_selectedManualVoucher?.isShippingDiscount == true) {
      return _selectedManualVoucher!.discount
          .clamp(0, _shippingBaseCost)
          .toDouble();
    }
    final calculated = _shippingBaseCost - _shippingCost;
    return calculated > 0 ? calculated : 0;
  }

  double get _grandTotal =>
      _checkoutPricing?.total.toDouble() ??
      (_itemsSubtotal + _shippingCost - _voucherDiscount)
          .clamp(0, double.infinity);

  String? get _freeShippingVoucherCodeForRequest =>
      _selectedRate.isSelfPickup ? null : _selectedFreeShippingVoucher?.code;

  bool get _hasSelectedShippingMethod => _shippingRateSelectedByUser;

  bool get _checkoutActionDisabled =>
      _voucherSyncFailed ||
      _syncingPricing ||
      _pricingRetryScheduled ||
      !_hasSelectedShippingMethod;

  @override
  void dispose() {
    _pricingRetryTimer?.cancel();
    _scrollController.removeListener(_handleCheckoutScroll);
    _scrollController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _handleCheckoutScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nearBottom = position.pixels >= position.maxScrollExtent - 120;
    if (nearBottom == _isNearBottom) return;
    setState(() => _isNearBottom = nearBottom);
  }

  Future<void> _loadCheckoutData() async {
    setState(() {
      _loadingRates = true;
      _shippingMessage = null;
    });

    try {
      if (memberStore.isLoggedIn) {
        final addresses = await memberService.fetchAddresses();
        if (addresses.isNotEmpty) {
          _addresses = addresses;
          _selectedAddress = _pickPrimaryAddress(addresses);
        } else {
          _addresses = const [];
          _selectedAddress = null;
        }
      }
      await _loadShippingRates();
      await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  Future<void> _loadShippingRates() async {
    final address = _selectedAddress;
    if (address == null || _checkoutItems.isEmpty) return;
    final result = await shippingService.fetchRates(
      address: address,
      items: _checkoutItems,
    );
    if (!mounted) return;
    if (!result.fromApi) {
      setState(() {
        _shippingRates = const [ShippingRate.selfPickup];
        _selectedRate = ShippingRate.selfPickup;
        _shippingRateSelectedByUser = false;
        _selectedFreeShippingVoucher = null;
        _shippingMessage =
            result.message ?? 'Ongkir belum dapat dihitung. Silakan coba lagi.';
      });
      return;
    }
    final courierRates =
        result.rates.where((rate) => !rate.isSelfPickup).toList();
    final rates = [ShippingRate.selfPickup, ...courierRates];
    final selectedRate = _resolveSelectedShippingRate(rates, courierRates);
    setState(() {
      _shippingRates = rates;
      _selectedRate = selectedRate;
      if (selectedRate.isSelfPickup) {
        _selectedFreeShippingVoucher = null;
      }
      _shippingMessage = result.instantUnavailableReason ?? result.message;
    });
  }

  ShippingRate _resolveSelectedShippingRate(
    List<ShippingRate> rates,
    List<ShippingRate> courierRates,
  ) {
    final previousRate = _selectedRate;
    final previousMatch = _findMatchingShippingRate(rates, previousRate);

    if (_shippingRateSelectedByUser) {
      if (previousMatch != null) return previousMatch;
      if (previousRate.isSelfPickup) return ShippingRate.selfPickup;
      return courierRates.isNotEmpty ? courierRates.first : rates.first;
    }

    // Internal pricing tetap memakai estimasi kurir delivery termurah supaya
    // voucher gratis ongkir bisa auto-apply. Namun UI tidak menandai metode
    // pengiriman sebagai terpilih sampai user memilih sendiri di sheet.
    return _cheapestDeliveryRate(courierRates) ?? rates.first;
  }

  ShippingRate? _findMatchingShippingRate(
    List<ShippingRate> rates,
    ShippingRate target,
  ) {
    for (final rate in rates) {
      if (rate.courierCode == target.courierCode &&
          rate.serviceCode == target.serviceCode) {
        return rate;
      }
    }
    return null;
  }

  ShippingRate? _cheapestDeliveryRate(List<ShippingRate> rates) {
    final availableRates = rates.where((rate) => rate.available).toList();
    if (availableRates.isEmpty) return null;
    availableRates.sort((a, b) => a.price.compareTo(b.price));
    return availableRates.first;
  }

  void _selectAddress(MemberAddress address) {
    final previousAddressId = _selectedAddress?.id;
    setState(() {
      _selectedAddress = address;
      if (previousAddressId != null && previousAddressId != address.id) {
        _shippingRateSelectedByUser = false;
      }
      _loadingRates = true;
    });
    _loadShippingRates().whenComplete(() {
      if (!mounted) return;
      setState(() => _loadingRates = false);
      _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
    });
  }

  Future<void> _openAddressSelectionPage() async {
    AppHaptics.tap();
    await Navigator.pushNamed(context, '/member/addresses');
    if (!mounted) return;

    setState(() {
      _loadingRates = true;
      _shippingMessage = null;
    });

    try {
      final previousAddressId = _selectedAddress?.id;
      final addresses = await memberService.fetchAddresses();
      if (!mounted) return;

      if (addresses.isEmpty) {
        setState(() {
          _addresses = const [];
          _selectedAddress = null;
          _shippingRates = const [ShippingRate.selfPickup];
          _selectedRate = ShippingRate.selfPickup;
          _loadingRates = false;
        });
        await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
        return;
      }

      final selectedAddress = addresses.firstWhere(
        (address) => address.isPrimary,
        orElse: () => addresses.firstWhere(
          (address) => address.id == previousAddressId,
          orElse: () => addresses.first,
        ),
      );

      setState(() => _addresses = addresses);
      _selectAddress(selectedAddress);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingRates = false);
      AppToast.showBanner(
        context,
        'Alamat gagal diperbarui: $error',
        kind: ToastKind.error,
      );
    }
  }

  String get _paymentProvider => _payment == 'Midtrans' ? 'MIDTRANS' : 'MANUAL';

  List<Map<String, dynamic>> _checkoutItemPayload() {
    return _checkoutItems.map((item) {
      final variant = item.variant;
      return {
        'productId': item.product.id,
        if (variant != null) 'variantId': variant.id,
        if (variant != null) 'variantLabel': item.variantLabel,
        'name': item.product.title,
        'price': item.effectivePrice.round(),
        'quantity': item.quantity,
        'weightGram': variant?.weightGram ?? item.product.weightGram,
      };
    }).toList();
  }

  void _cancelPricingRetry() {
    _pricingRetryTimer?.cancel();
    _pricingRetryTimer = null;
  }

  String _pricingSyncErrorMessage(Object? error) {
    final text = error?.toString().trim();
    if (text == null || text.isEmpty) {
      return 'Koneksi ke server checkout belum stabil.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  void _schedulePricingRetry({
    required bool autoApply,
    Object? error,
  }) {
    if (!mounted || _checkoutItems.isEmpty) return;

    if (_pricingRetryAttempt >= _maxPricingSyncRetries) {
      setState(() {
        _pricingRetryScheduled = false;
        _voucherSyncFailed = true;
        _pricingSyncError = _pricingSyncErrorMessage(error);
      });
      return;
    }

    final attempt = _pricingRetryAttempt + 1;
    final delay = _pricingSyncRetryDelays[
        (attempt - 1).clamp(0, _pricingSyncRetryDelays.length - 1)];

    _cancelPricingRetry();
    setState(() {
      _pricingRetryAttempt = attempt;
      _pricingRetryScheduled = true;
      _voucherSyncFailed = false;
      _pricingSyncError = _pricingSyncErrorMessage(error);
    });

    _pricingRetryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _pricingRetryScheduled = false);
      _syncCheckoutPricing(autoApply: autoApply, resetRetry: false);
    });
  }

  Future<void> _syncCheckoutPricing({
    required bool autoApply,
    bool resetRetry = true,
  }) async {
    if (_checkoutItems.isEmpty) {
      if (!mounted) return;
      _cancelPricingRetry();
      setState(() {
        _checkoutPricing = null;
        _selectedFreeShippingVoucher = null;
        _selectedProductVoucher = null;
        _selectedLoyaltyVoucher = null;
        _selectedManualVoucher = null;
        _availableVouchers = const [];
        _unavailableVouchers = const [];
        _voucherSyncFailed = false;
        _pricingRetryScheduled = false;
        _pricingRetryAttempt = 0;
        _pricingSyncError = null;
      });
      return;
    }

    if (resetRetry) {
      _cancelPricingRetry();
    }

    setState(() {
      _syncingPricing = true;
      _loadingVouchers = true;
      if (resetRetry) {
        _pricingRetryScheduled = false;
        _pricingRetryAttempt = 0;
        _pricingSyncError = null;
      }
      _voucherSyncFailed = false;
      if (_selectedRate.isSelfPickup) {
        _selectedFreeShippingVoucher = null;
      }
    });
    try {
      final recalc = await checkoutService.recalculate(
        items: _checkoutItemPayload(),
        shippingFee: _selectedRate.price,
        voucherCode: _selectedProductVoucher?.code,
        customerVoucherCode: _selectedProductVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
        freeShippingVoucherCode: _freeShippingVoucherCodeForRequest,
        productVoucherCode: _selectedProductVoucher?.code,
        loyaltyVoucherCode: _selectedLoyaltyVoucher?.code,
        privateVoucherCode: _selectedManualVoucher?.code,
        autoApply: autoApply,
        address: _selectedAddress,
        shippingRate: _selectedRate,
        paymentProvider: _paymentProvider,
        // Saldo Refund — kirim nilai sangat besar kalau toggle ON;
        // server clamp ke min(wallet, totalBeforeRefund). Server return
        // refundBalanceAvailable + refundBalanceUsed di response.
        refundBalanceUsed: _useRefundBalance ? 999999999 : 0,
      );
      if (!mounted || recalc == null) {
        _schedulePricingRetry(
          autoApply: autoApply,
          error: checkoutService.lastRecalculateError,
        );
        return;
      }

      setState(() {
        _checkoutPricing = recalc;
        _voucherSyncFailed = false;
        _pricingRetryScheduled = false;
        _pricingRetryAttempt = 0;
        _pricingSyncError = null;
        // Resolve each slot dari backend response (multi-field redundancy).
        final freeShip = recalc.appliedFreeShippingVoucher;
        final product = recalc.appliedProductVoucher ??
            (recalc.appliedCustomerVoucher?.isProductDiscount == true
                ? recalc.appliedCustomerVoucher
                : null);
        final loyalty = recalc.appliedLoyaltyVoucher ??
            (recalc.appliedCustomerVoucher?.isLoyaltyClaim == true
                ? recalc.appliedCustomerVoucher
                : null);
        var manual =
            recalc.appliedPrivateVoucher ?? recalc.appliedManualVoucher;
        // BUSINESS RULE: max 1 voucher per business-type (ongkir / produk /
        // reward poin / manual). Backend kadang return manual voucher yang
        // type-nya loyalty atau product (legacy / private grant) — kalau
        // begitu, dia overlap dengan slot loyalty/product yang sudah ada
        // → user lihat 2 voucher reward poin (atau 2 diskon produk) tampil
        // bareng. Defensive drop manual kalau collides dengan slot lain
        // yang punya business-type sama.
        if (manual != null && loyalty != null && manual.isLoyaltyClaim) {
          // Manual carries loyalty type, AND loyalty slot already filled →
          // drop manual to enforce "max 1 reward poin" rule.
          manual = null;
        }
        if (manual != null &&
            product != null &&
            manual.isProductDiscount &&
            !manual.isPrivateManual) {
          manual = null;
        }
        if (manual != null && freeShip != null && manual.isFreeShipping) {
          manual = null;
        }
        _selectedFreeShippingVoucher = freeShip;
        _selectedProductVoucher = product;
        _selectedLoyaltyVoucher = loyalty;
        _selectedManualVoucher = manual;
        _availableVouchers = recalc.availableVouchers;
        _unavailableVouchers = recalc.unavailableVouchers;
      });
      // Defensive auto-apply fallback — kalau backend SKIP auto-apply
      // untuk slot tertentu padahal availableVouchers punya match,
      // Flutter pilih best voucher dari available list + trigger re-sync
      // dengan explicit code. Cover edge case backend resolveCustomerSlot
      // skip slot karena alasan apapun (subtotal threshold, eligibility,
      // race condition). Per business rule Natalo: max 1 per type, semua
      // 3 type auto-apply kalau eligible.
      if (autoApply && !_autoVoucherSuppressed) {
        final shouldReSync = _ensureAutoApplyFallback(recalc);
        if (shouldReSync) {
          // Re-sync dengan code yang baru dipilih supaya backend
          // confirm + populate discount values. Set autoApply: false
          // supaya backend tidak override pilihan kita.
          await _syncCheckoutPricing(autoApply: false, resetRetry: false);
          return;
        }
      }
      final voucherError =
          recalc.manualVoucherError ?? recalc.customerVoucherError;
      if (voucherError != null && voucherError.isNotEmpty && mounted) {
        // Kind-inference: field ini datang dari manualVoucherError /
        // customerVoucherError — namanya sendiri sudah "Error" → error.
        AppToast.showBanner(context, voucherError, kind: ToastKind.error);
      }
    } catch (error) {
      if (!mounted) return;
      _schedulePricingRetry(autoApply: autoApply, error: error);
    } finally {
      if (mounted) {
        setState(() {
          _syncingPricing = false;
          _loadingVouchers = false;
        });
      }
    }
  }

  Future<void> _applyManualVoucherCode(String rawCode) async {
    final code = rawCode.trim();
    AppHaptics.tap();
    setState(() {
      if (code.isEmpty) {
        _selectedManualVoucher = null;
      } else {
        _selectedManualVoucher = MemberVoucher(
          code: code,
          title: 'Kode promo $code',
          description: 'Menunggu validasi server.',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          type: 'PRIVATE_MANUAL_CODE',
          visibility: 'PRIVATE',
          discountScope: 'PRODUCT',
        );
      }
      _autoVoucherSuppressed = false;
    });
    await _syncCheckoutPricing(autoApply: true);
    if (!mounted) return;
    if (code.isNotEmpty && _selectedManualVoucher != null) {
      AppHaptics.success();
    }
  }

  /// Defensive: scan availableVouchers + isi slot yang kosong dengan
  /// best voucher per type. Per business rule Natalo: max 1 per type
  /// (gratis ongkir / diskon produk / reward poin), semua auto-apply
  /// kalau eligible. Backend `resolveCustomerSlot` sudah punya logic
  /// auto-pick tapi kadang skip (race condition / data quirk). Helper
  /// ini covers gap di client side.
  ///
  /// Return true kalau ada slot yang baru di-isi (caller harus re-sync
  /// supaya backend confirm + kalkulasi discount).
  bool _ensureAutoApplyFallback(CheckoutRecalcResult recalc) {
    var changed = false;
    final available = recalc.availableVouchers;

    // Slot product: kalau kosong, pick best PUBLIC_PRODUCT_DISCOUNT.
    if (_selectedProductVoucher == null) {
      final candidate = available
          .where((v) =>
              v.isProductDiscount &&
              !v.isLoyaltyClaim &&
              !v.isPrivateManual &&
              !v.isBrandExclusive)
          .toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
      if (candidate.isNotEmpty) {
        _selectedProductVoucher = candidate.first;
        changed = true;
      }
    }

    // Slot loyalty: kalau kosong, pick best LOYALTY_POINT_CLAIM.
    if (_selectedLoyaltyVoucher == null) {
      final candidate = available.where((v) => v.isLoyaltyClaim).toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
      if (candidate.isNotEmpty) {
        _selectedLoyaltyVoucher = candidate.first;
        changed = true;
      }
    }

    // Slot shipping: kalau kosong, pick best FREE_SHIPPING.
    // Skip kalau Self-Pickup karena tidak butuh free shipping voucher.
    if (_selectedFreeShippingVoucher == null && !_selectedRate.isSelfPickup) {
      final candidate = available
          .where((v) =>
              (v.isFreeShipping || v.isShippingDiscount) && !v.isBrandExclusive)
          .toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
      if (candidate.isNotEmpty) {
        _selectedFreeShippingVoucher = candidate.first;
        changed = true;
      }
    }

    return changed;
  }

  Future<void> _applyVoucher(MemberVoucher voucher) async {
    AppHaptics.tap();
    setState(() {
      _autoVoucherSuppressed = true;
      if (voucher.isFreeShipping || voucher.isShippingDiscount) {
        _selectedFreeShippingVoucher = voucher;
      } else if (voucher.isLoyaltyClaim) {
        _selectedLoyaltyVoucher = voucher;
      } else if (voucher.isPrivateManual) {
        _selectedManualVoucher = voucher;
      } else {
        _selectedProductVoucher = voucher;
      }
    });
    await _syncCheckoutPricing(autoApply: false);
    if (mounted) AppHaptics.success();
  }

  Future<void> _removeVoucher(MemberVoucher voucher) async {
    AppHaptics.tap();
    setState(() {
      _autoVoucherSuppressed = true;
      if (_selectedFreeShippingVoucher != null &&
          _sameVoucher(_selectedFreeShippingVoucher!, voucher)) {
        _selectedFreeShippingVoucher = null;
      }
      if (_selectedProductVoucher != null &&
          _sameVoucher(_selectedProductVoucher!, voucher)) {
        _selectedProductVoucher = null;
      }
      if (_selectedLoyaltyVoucher != null &&
          _sameVoucher(_selectedLoyaltyVoucher!, voucher)) {
        _selectedLoyaltyVoucher = null;
      }
      if (_selectedManualVoucher != null &&
          _sameVoucher(_selectedManualVoucher!, voucher)) {
        _selectedManualVoucher = null;
      }
    });
    await _syncCheckoutPricing(autoApply: false);
  }

  Future<void> _openVoucherDetailsSheet() async {
    AppHaptics.tap();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CheckoutVoucherDetailsSheet(
        selected: [
          _selectedFreeShippingVoucher,
          _selectedProductVoucher,
          _selectedLoyaltyVoucher,
          _selectedManualVoucher,
        ].whereType<MemberVoucher>().toList(),
        available: _availableVouchers,
        unavailable: _unavailableVouchers,
        loading: _loadingVouchers || _syncingPricing,
        onApply: _applyVoucher,
        onRemove: _removeVoucher,
      ),
    );
  }

  Future<void> _openProductsSheet() async {
    AppHaptics.tap();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _CheckoutProductsSheet(items: _checkoutItems),
    );
  }

  Future<void> _openNoteSheet() async {
    AppHaptics.tap();
    final draft = TextEditingController(text: _noteController.text);
    final saved = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _CheckoutNoteSheet(controller: draft),
    );
    draft.dispose();
    if (!mounted || saved == null) return;
    setState(() => _noteController.text = saved.trim());
  }

  Future<void> _openShippingSheet() async {
    AppHaptics.tap();
    final picked = await showModalBottomSheet<ShippingRate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _ShippingMethodSheet(
        rates: _shippingRates,
        selected: _selectedRate,
        hasSelection: _hasSelectedShippingMethod,
        loading: _loadingRates,
        message: _shippingMessage,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _shippingRateSelectedByUser = true;
      _selectedRate = picked;
      if (picked.isSelfPickup) {
        _selectedFreeShippingVoucher = null;
      }
    });
    await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
  }

  Future<void> _openStoreMaps() async {
    AppHaptics.tap();
    final uri = Uri.parse(PickupStoreInfo.mapsUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    AppToast.showBanner(
      context,
      'Tidak bisa membuka Google Maps.',
      kind: ToastKind.error,
    );
  }

  Future<void> _openPaymentSheet() async {
    AppHaptics.tap();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _PaymentMethodSheet(selected: _payment),
    );
    if (!mounted || picked == null || picked == _payment) return;
    setState(() => _payment = picked);
    await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
  }

  Future<void> _placeOrder() async {
    // BUGFIX(audit): guard re-entry. Tombol "Buat Pesanan" ada di DUA tempat
    // (bottom bar + final payment panel) & disable-nya baru efektif setelah
    // rebuild. Dua tap nyaris bersamaan bisa lolos sebelum disable → kirim
    // createOrder 2x (order duplikat). Early-return kalau sudah submitting.
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final profile = memberStore.profile;
      final address = _selectedAddress;
      if (address == null) {
        throw Exception('Alamat pengiriman belum tersedia.');
      }
      if (!_hasSelectedShippingMethod) {
        throw Exception('Pilih metode pengiriman terlebih dahulu.');
      }
      // Step 1 — validate cart server-side. Catch stok kurang / harga
      // berubah SEBELUM hit createOrder (server tetap validate, tapi UX
      // lebih bagus kalau user dapat issue list dulu).
      final validation = await cartService.validate(_checkoutItems);
      if (!mounted) return;
      if (!validation.valid && validation.issues.isNotEmpty) {
        AppHaptics.warning();
        AppToast.showBanner(
          context,
          'Beberapa item perlu update: ${validation.issues.first.message}',
          kind: ToastKind.warning,
          duration: const Duration(seconds: 5),
        );
        setState(() => _submitting = false);
        return;
      }
      // Step 2 — server-side recalc untuk verify total. Kalau server return
      // total beda dari client (mis. harga produk baru update, voucher rules
      // berubah), beri user kesempatan review sebelum hit createOrder.
      final recalc = await checkoutService.recalculate(
        items: _checkoutItemPayload(),
        shippingFee: _selectedRate.price,
        voucherCode: _selectedProductVoucher?.code,
        customerVoucherCode: _selectedProductVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
        freeShippingVoucherCode: _freeShippingVoucherCodeForRequest,
        productVoucherCode: _selectedProductVoucher?.code,
        loyaltyVoucherCode: _selectedLoyaltyVoucher?.code,
        privateVoucherCode: _selectedManualVoucher?.code,
        autoApply: !_autoVoucherSuppressed,
        address: address,
        shippingRate: _selectedRate,
        paymentProvider: _paymentProvider,
        refundBalanceUsed: _useRefundBalance ? 999999999 : 0,
      );
      if (!mounted) return;
      if (recalc != null) {
        final diff = (recalc.total - _grandTotal).abs();
        // Tolerance 100 Rupiah — server kadang rounding minor beda dengan
        // client (mis. tax rounding). Diff > 100 = real change yang user
        // perlu review.
        if (diff > 100) {
          final accept = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Total Berubah',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              content: Text(
                'Total final dari server: ${formatRupiah(recalc.total)}.\n'
                '(Sebelumnya: ${formatRupiah(_grandTotal)})\n\n'
                'Lanjutkan checkout dengan total baru?',
                style: const TextStyle(height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Lanjutkan'),
                ),
              ],
            ),
          );
          if (accept != true || !mounted) {
            setState(() => _submitting = false);
            return;
          }
        }
      }
      final result = await orderService.createOrder(
        // Use override items kalau Buy Now flow, else cartStore.items.
        items: _checkoutItems,
        customerName: profile?.name ?? 'Member Natalo',
        customerPhone: profile?.phone ?? '081330003880',
        customerEmail: profile?.email ?? 'member@natalopetshop.com',
        address: address,
        shippingRate: _selectedRate,
        paymentProvider: _paymentProvider,
        voucherCode: _selectedProductVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
        freeShippingVoucherCode: _freeShippingVoucherCodeForRequest,
        productVoucherCode: _selectedProductVoucher?.code,
        loyaltyVoucherCode: _selectedLoyaltyVoucher?.code,
        privateVoucherCode: _selectedManualVoucher?.code,
        // Saldo Refund — pass server-validated value dari recalc (sudah
        // clamped ke wallet balance + total). Kalau toggle OFF, value 0.
        refundBalanceUsed: _useRefundBalance
            ? (_checkoutPricing?.refundBalanceUsed.toInt() ?? 0)
            : 0,
        notes: _noteController.text,
      );
      if (!mounted) return;
      AppHaptics.success();
      // Analytics: conversion event utama — track purchase value + item count
      // untuk funnel + revenue dashboard. No-op kalau Firebase belum setup.
      AppAnalytics.logPurchase(
        transactionId: result.orderNumber,
        value: _grandTotal.round(),
      );
      if (!mounted) return;
      _openOrderSuccess(result);
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.showBanner(
        context,
        'Checkout gagal: $error',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openOrderSuccess(OrderResult result) {
    final createdOrder = _createdOrderSummary(result);
    final purchasedProductIds = _checkoutItems
        .map((item) => item.product.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    _clearOrderedItemsFromCart();
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/order-success',
      ModalRoute.withName('/'),
      arguments: OrderSuccessArgs(
        order: createdOrder,
        purchasedProductIds: purchasedProductIds,
      ),
    );
  }

  OrderSummary _createdOrderSummary(OrderResult result) {
    return OrderSummary(
      id: result.orderNumber,
      orderNumber: result.orderNumber,
      status: result.status ?? 'PENDING',
      paymentStatus: result.paymentStatus ?? 'PENDING',
      paymentProvider: result.paymentProvider ?? _paymentProvider,
      paymentUrl: result.paymentUrl,
      manualBank: result.manualBank ??
          (_paymentProvider == 'MANUAL' ? 'BCA_NATASHA' : null),
      uniqueCode: result.uniqueCode,
      paymentDeadline: result.paymentDeadline,
      trackingToken: result.trackingToken,
      detailUrl: result.detailUrl,
      createdAt: DateTime.now(),
      itemCountFromApi:
          _checkoutItems.fold<int>(0, (sum, item) => sum + item.quantity),
      subtotal: _itemsSubtotal,
      shippingCost: _shippingCost,
      discount: _voucherDiscount,
      total: _grandTotal,
      items: _checkoutItems.map((item) {
        return OrderItemSummary(
          id: item.product.id,
          productId: item.product.id,
          name: item.product.title,
          quantity: item.quantity,
          // BUGFIX(audit): pakai effectivePrice (harga varian/yang ditagih),
          // bukan product.finalPrice (harga base). Untuk produk bervarian,
          // summary order sebelumnya tampil harga base yang SALAH (tidak
          // sesuai yang dibayar). Payload order sebenarnya pakai
          // effectivePrice juga.
          price: item.effectivePrice.round(),
          imageUrl: item.product.imageUrl,
          categoryName: item.product.category,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cartStore,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        if (_redirectingToLogin) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: const Center(
              child: CircularProgressIndicator(color: _brandBlue),
            ),
          );
        }
        final items = _checkoutItems;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            // Smart back: kalau ada benefit aktif (voucher / ongkir / points),
            // tampilkan dialog detail. Else dialog konfirmasi sederhana.
            final shouldPop = await _confirmBackToCart(context);
            if (shouldPop && context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: cs.surface,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: cs.surface,
              automaticallyImplyLeading: false,
              // Judul rata kiri ikut theme default & sisa alur belanja
              // (Keranjang/Detail Produk/Pesanan) — sebelumnya di-tengah
              // sendirian, bikin judul loncat saat cart -> checkout.
              leading: IconButton(
                tooltip: 'Kembali',
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: cs.onSurface,
                ),
                onPressed: () async {
                  AppHaptics.tap();
                  final shouldPop = await _confirmBackToCart(context);
                  if (shouldPop && context.mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
              title: Text(
                'Checkout',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            body: items.isEmpty
                ? const _EmptyCheckoutState()
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _CheckoutAddressCard(
                        selected: _selectedAddress,
                        onTap: _openAddressSelectionPage,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutProductsSummaryCard(
                        items: items,
                        onViewAll: items.length > 3 ? _openProductsSheet : null,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutNoteTile(
                        note: _noteController.text,
                        onTap: _openNoteSheet,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutShippingMethodCard(
                        rates: _shippingRates,
                        selected: _selectedRate,
                        hasSelection: _hasSelectedShippingMethod,
                        loading: _loadingRates,
                        message: _shippingMessage,
                        onOpenMaps: _openStoreMaps,
                        onTap: _openShippingSheet,
                      ),
                      const SizedBox(height: 12),
                      _VoucherSlot(
                        freeShippingVoucher: _selectedFreeShippingVoucher,
                        productVoucher: _selectedProductVoucher,
                        loyaltyVoucher: _selectedLoyaltyVoucher,
                        manualSelected: _selectedManualVoucher,
                        availableVouchers: _availableVouchers,
                        unavailableVouchers: _unavailableVouchers,
                        loading: _loadingVouchers,
                        onViewVouchers: _openVoucherDetailsSheet,
                        onApplyManualCode: _applyManualVoucherCode,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutPaymentMethodCard(
                        payment: _payment,
                        onTap: _openPaymentSheet,
                      ),
                      // Saldo Refund — render hanya kalau user punya saldo
                      // available. Toggle ON/OFF recompute pricing.
                      if ((_checkoutPricing?.refundBalanceAvailable ?? 0) >
                          0) ...[
                        const SizedBox(height: 12),
                        _RefundBalanceCard(
                          available: _checkoutPricing!.refundBalanceAvailable
                              .toDouble(),
                          used: _useRefundBalance
                              ? _checkoutPricing!.refundBalanceUsed.toDouble()
                              : 0,
                          enabled: _useRefundBalance,
                          syncing: _syncingPricing,
                          onChanged: (value) {
                            setState(() => _useRefundBalance = value);
                            _syncCheckoutPricing(
                              autoApply: !_autoVoucherSuppressed,
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      _PaymentSummaryCard(
                        subtotal: _itemsSubtotal,
                        shippingBaseCost: _shippingBaseCost,
                        shippingCost: _shippingCost,
                        productDiscount: _productDiscount,
                        shippingDiscount: _shippingDiscount,
                        refundBalanceUsed: _useRefundBalance
                            ? (_checkoutPricing?.refundBalanceUsed.toDouble() ??
                                0)
                            : 0,
                        grandTotal: _grandTotal,
                        syncing: _syncingPricing,
                        syncRetrying: _pricingRetryScheduled,
                        syncFailed: _voucherSyncFailed,
                        syncError: _pricingSyncError,
                        onRetrySync: () => _syncCheckoutPricing(
                          autoApply: !_autoVoucherSuppressed,
                        ),
                      ),
                      _CheckoutSavingsStrip(
                        productDiscount: _productDiscount,
                        shippingDiscount: _shippingDiscount,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutFinalPaymentPanel(
                        total: _grandTotal,
                        submitting: _submitting,
                        disabled: _checkoutActionDisabled,
                        onPressed: _placeOrder,
                      ),
                      const SizedBox(height: 96),
                    ],
                  ),
            bottomNavigationBar: items.isEmpty
                ? null
                : _CheckoutBottomBar(
                    total: _grandTotal,
                    productDiscount: _productDiscount,
                    shippingDiscount: _shippingDiscount,
                    submitting: _submitting,
                    disabled: _checkoutActionDisabled,
                    onPressed: _placeOrder,
                    visible: !_isNearBottom,
                  ),
          ),
        );
      },
    );
  }

  /// Smart back-to-cart confirmation. Match screenshot UI Capacitor:
  /// - **Dengan voucher aktif / ongkir / poin**: dialog "Voucher kamu masih aktif!"
  ///   yang highlight benefit list yang akan hilang.
  /// - **Tanpa benefit aktif**: dialog ringan "Yakin kembali ke keranjang?"
  Future<bool> _confirmBackToCart(BuildContext context) async {
    final voucherDiscount = _voucherDiscount;
    // Loyalty earn formula match backend di /api/orders/route.ts:501 —
    // Math.floor(total / 20000). Tetap konsisten supaya angka yang
    // di-display di dialog sama persis dengan yang user akan dapat
    // setelah order DELIVERED.
    final earnedPoints = (_grandTotal / 20000).floor();
    final hasActiveBenefit = voucherDiscount > 0 || earnedPoints > 0;
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _BackToCartDialog(
        showBenefits: hasActiveBenefit,
        voucherDiscount: voucherDiscount,
        earnedPoints: earnedPoints,
      ),
    );
    return result == true;
  }
}

/// Modal "Voucher masih aktif" / "Yakin kembali ke keranjang" — match PWA
/// confirmation pop-up + screenshot user (e-commerce convention).
///
/// Saat ada benefit aktif (voucher > 0 ATAU earnedPoints > 0), tampilkan
/// rincian yang akan hilang:
///   - Row "Hemat Voucher" (kalau voucherDiscount > 0)
///   - Row "Poin yang didapat" (kalau earnedPoints > 0)
/// Kedua row mungkin muncul bareng, atau salah satu, tergantung state.
///
/// Saat tidak ada benefit aktif, konfirmasi ringan tanpa detail.
class _BackToCartDialog extends StatelessWidget {
  final bool showBenefits;
  final double voucherDiscount;
  final int earnedPoints;

  const _BackToCartDialog({
    required this.showBenefits,
    required this.voucherDiscount,
    this.earnedPoints = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasVoucher = voucherDiscount > 0;
    final hasPoints = earnedPoints > 0;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header icon.
                Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                        : const Color(0xFFEAF5FF),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    showBenefits
                        ? Icons.confirmation_number_rounded
                        : Icons.shopping_cart_outlined,
                    color: _brandBlue,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  showBenefits
                      ? (hasVoucher
                          ? 'Voucher kamu masih aktif!'
                          : 'Lanjut order, dapat poin!')
                      : 'Yakin kembali ke keranjang?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                if (showBenefits) ...[
                  _BenefitSummaryText(
                    voucherDiscount: voucherDiscount,
                    earnedPoints: earnedPoints,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        if (hasVoucher)
                          _BenefitRow(
                            icon: Icons.confirmation_number_rounded,
                            iconColor: const Color(0xFFEF5A47),
                            iconBg: const Color(0xFFFDECE7),
                            label: 'Hemat Voucher',
                            value: formatRupiah(voucherDiscount),
                            valueColor: NataloColors.discountRed,
                          ),
                        if (hasVoucher && hasPoints) const SizedBox(height: 10),
                        if (hasPoints)
                          _BenefitRow(
                            icon: Icons.monetization_on_rounded,
                            iconColor: const Color(0xFFE0A52E),
                            iconBg: const Color(0xFFFFF4D6),
                            label: 'Poin yang didapat',
                            value: '$earnedPoints poin',
                            valueColor: const Color(0xFFB45309),
                          ),
                      ],
                    ),
                  ),
                ] else
                  Text(
                    'Pesanan kamu belum selesai.\nKamu bisa lanjut checkout atau kembali mengatur keranjang.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.55,
                    ),
                  ),
                const SizedBox(height: 18),
                // Primary CTA: Lanjut Checkout (close dialog, stay)
                ElevatedButton(
                  onPressed: () {
                    AppHaptics.tap();
                    Navigator.pop(context, false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('Lanjut Checkout'),
                ),
                const SizedBox(height: 4),
                // Secondary: Kembali ke Keranjang — TEXT LINK style (no
                // border) match screenshot reference. TextButton dengan
                // bold + dark color supaya tetap discoverable tapi
                // visually subordinate dari primary CTA.
                TextButton(
                  onPressed: () {
                    AppHaptics.tap();
                    Navigator.pop(context, true);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Kembali ke Keranjang'),
                ),
              ],
            ),
          ),
          // Close (X) button top-right corner — match screenshot pattern.
          // Tap → same dengan "Kembali ke Keranjang" (return true → pop
          // checkout). Quick exit untuk user yang yakin keluar.
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  AppHaptics.tap();
                  Navigator.pop(context, true);
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtitle text inside dialog — adaptasi pesan berdasar combo benefit.
/// Cuma voucher: "Kamu sedang hemat Rp X di checkout ini..."
/// Cuma poin:    "Kamu akan dapat X poin..."
/// Keduanya:     "Kamu hemat Rp X + dapat X poin..."
class _BenefitSummaryText extends StatelessWidget {
  final double voucherDiscount;
  final int earnedPoints;

  const _BenefitSummaryText({
    required this.voucherDiscount,
    required this.earnedPoints,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasVoucher = voucherDiscount > 0;
    final hasPoints = earnedPoints > 0;
    final baseStyle = TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.55,
    );
    final bold = baseStyle.copyWith(
      color: NataloColors.discountRed,
      fontWeight: FontWeight.w900,
    );
    final boldPoint = baseStyle.copyWith(
      color: const Color(0xFFB45309),
      fontWeight: FontWeight.w900,
    );
    if (hasVoucher && hasPoints) {
      return Text.rich(
        TextSpan(
          text: 'Kamu sedang hemat ',
          style: baseStyle,
          children: [
            TextSpan(text: formatRupiah(voucherDiscount), style: bold),
            const TextSpan(text: ' + bakal dapat '),
            TextSpan(text: '$earnedPoints poin', style: boldPoint),
            const TextSpan(text: ' kalau lanjut checkout.'),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    if (hasVoucher) {
      return Text.rich(
        TextSpan(
          text: 'Kamu sedang hemat ',
          style: baseStyle,
          children: [
            TextSpan(text: formatRupiah(voucherDiscount), style: bold),
            const TextSpan(text: ' di checkout ini.\n'),
            const TextSpan(
                text: 'Lanjutkan pesanan agar voucher tidak terlewat.'),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    // Hanya poin (kasus rare — voucher null tapi total cukup besar untuk
    // earn poin). Tetap show supaya user aware dapat poin loyalty.
    return Text.rich(
      TextSpan(
        text: 'Lanjut checkout untuk dapat ',
        style: baseStyle,
        children: [
          TextSpan(text: '$earnedPoints poin', style: boldPoint),
          const TextSpan(text: ' Natalo.\nPoin bisa ditukar voucher di Akun.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? iconBg;
  final String label;
  final String value;
  final Color valueColor;

  const _BenefitRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
    this.iconBg,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 32,
          width: 32,
          decoration: BoxDecoration(
            color: iconBg ?? iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CheckoutCardShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const _CheckoutCardShell({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: cs.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.outlineVariant
                    : const Color(0xFFE8EEF7),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CheckoutSectionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;

  const _CheckoutSectionIcon({
    required this.icon,
    this.color = _brandBlue,
    this.background = const Color(0xFFEAF3FF),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Soft pastel blue tile behind a blue icon → adapt in dark.
    final effectiveBackground =
        (isDark && background == const Color(0xFFEAF3FF))
            ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
            : background;
    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: effectiveBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _ShippingMethodIcon extends StatelessWidget {
  final ShippingRate rate;
  final bool disabled;
  final double size;

  const _ShippingMethodIcon({
    required this.rate,
    this.disabled = false,
    this.size = 42,
  });

  _ShippingIconSpec get _spec => _ShippingIconSpec.fromRate(rate);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = _spec;
    final bg = disabled ? cs.surfaceContainerHighest : spec.background;
    final fg = disabled ? cs.onSurfaceVariant : spec.foreground;

    return Container(
      height: size,
      width: size,
      padding: EdgeInsets.all(spec.assetPath == null ? 0 : size * 0.19),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: spec.assetPath == null
          ? _ShippingIconFallback(
              spec: spec,
              color: fg,
              disabled: disabled,
            )
          : Image.asset(
              spec.assetPath!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _ShippingIconFallback(
                spec: spec,
                color: fg,
                disabled: disabled,
              ),
            ),
    );
  }
}

class _ShippingIconSpec {
  final _ShippingIconKind kind;
  final String? assetPath;
  final IconData fallbackIcon;
  final Color background;
  final Color foreground;
  final String? label;

  const _ShippingIconSpec({
    required this.kind,
    required this.fallbackIcon,
    required this.background,
    required this.foreground,
    this.assetPath,
    this.label,
  });

  factory _ShippingIconSpec.fromRate(ShippingRate rate) {
    final code =
        rate.courierCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final service =
        rate.serviceCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final type =
        rate.serviceType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final name = '${rate.courierName} ${rate.serviceName}'.toLowerCase();
    final haystack = '$code $service $type $name';

    if (rate.isSelfPickup ||
        haystack.contains('selfpickup') ||
        haystack.contains('pickup')) {
      return const _ShippingIconSpec(
        kind: _ShippingIconKind.icon,
        assetPath: 'assets/icons/shipping/pickup_store.png',
        fallbackIcon: Icons.storefront_rounded,
        background: Color(0xFFEAF3FF),
        foreground: _brandBlue,
      );
    }
    if (haystack.contains('gojek') || haystack.contains('gosend')) {
      return const _ShippingIconSpec(
        kind: _ShippingIconKind.brandText,
        assetPath: 'assets/icons/shipping/gojek.png',
        fallbackIcon: Icons.two_wheeler_rounded,
        background: Color(0xFFEAF8EF),
        foreground: Color(0xFF00AA13),
        label: 'Go',
      );
    }
    if (haystack.contains('grab')) {
      return const _ShippingIconSpec(
        kind: _ShippingIconKind.brandText,
        assetPath: 'assets/icons/shipping/grab.png',
        fallbackIcon: Icons.two_wheeler_rounded,
        background: Color(0xFFEAF8EF),
        foreground: Color(0xFF00B14F),
        label: 'Grab',
      );
    }
    if (haystack.contains('jnt') || haystack.contains('jandt')) {
      return const _ShippingIconSpec(
        kind: _ShippingIconKind.brandText,
        assetPath: 'assets/icons/shipping/jnt.png',
        fallbackIcon: Icons.local_shipping_rounded,
        background: Color(0xFFFFF1F2),
        foreground: Color(0xFFE11D48),
        label: 'J&T',
      );
    }
    if (haystack.contains('jtr') ||
        haystack.contains('trucking') ||
        haystack.contains('truck')) {
      return const _ShippingIconSpec(
        kind: _ShippingIconKind.jneTrucking,
        assetPath: 'assets/icons/shipping/jne_trucking.png',
        fallbackIcon: Icons.local_shipping_rounded,
        background: Color(0xFFEAF3FF),
        foreground: Color(0xFF0B5CAD),
        label: 'JNE',
      );
    }
    if (haystack.contains('jne')) {
      return const _ShippingIconSpec(
        kind: _ShippingIconKind.jne,
        assetPath: 'assets/icons/shipping/jne.png',
        fallbackIcon: Icons.local_shipping_rounded,
        background: Color(0xFFEAF3FF),
        foreground: Color(0xFF0B5CAD),
        label: 'JNE',
      );
    }

    return const _ShippingIconSpec(
      kind: _ShippingIconKind.icon,
      fallbackIcon: Icons.local_shipping_rounded,
      background: Color(0xFFEAF3FF),
      foreground: _brandBlue,
    );
  }
}

enum _ShippingIconKind { icon, brandText, jne, jneTrucking }

class _ShippingIconFallback extends StatelessWidget {
  final _ShippingIconSpec spec;
  final Color color;
  final bool disabled;

  const _ShippingIconFallback({
    required this.spec,
    required this.color,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    switch (spec.kind) {
      case _ShippingIconKind.icon:
        return Icon(spec.fallbackIcon, color: color, size: 22);
      case _ShippingIconKind.brandText:
        return Center(
          child: Text(
            spec.label ?? '',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: (spec.label?.length ?? 0) > 3 ? 11 : 14,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        );
      case _ShippingIconKind.jne:
      case _ShippingIconKind.jneTrucking:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                spec.label ?? 'JNE',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                height: 3,
                width: 20,
                decoration: BoxDecoration(
                  color: disabled ? color : const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              if (spec.kind == _ShippingIconKind.jneTrucking)
                Text(
                  'JTR',
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        );
    }
  }
}

class _CheckoutAddressCard extends StatelessWidget {
  final MemberAddress? selected;
  final VoidCallback onTap;

  const _CheckoutAddressCard({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CheckoutCardShell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CheckoutSectionIcon(icon: Icons.location_on_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alamat Pengiriman',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  selected?.recipient.isNotEmpty == true
                      ? selected!.recipient
                      : 'Alamat belum dipilih',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    selected!.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (selected!.phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      selected!.phone,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 3),
                  Text(
                    'Pilih alamat member untuk melanjutkan checkout.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _CheckoutProductsSummaryCard extends StatelessWidget {
  final List<CartItem> items;
  final VoidCallback? onViewAll;

  const _CheckoutProductsSummaryCard({
    required this.items,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final previewItems = items.take(3).toList();
    final totalQty = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final remaining = items.length - previewItems.length;
    return _CheckoutCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CheckoutSectionIcon(icon: Icons.shopping_bag_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ringkasan Produk dibeli',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalQty produk dalam pesanan',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...previewItems.indexed.map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: index == previewItems.length - 1 ? 0 : 12),
              child: _CheckoutProductRow(item: item),
            );
          }),
          if (remaining > 0 && onViewAll != null) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: Theme.of(context).brightness == Brightness.dark
                  ? cs.outlineVariant
                  : const Color(0xFFE8EEF7),
            ),
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.only(top: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lihat $remaining produk lainnya',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckoutProductRow extends StatelessWidget {
  final CartItem item;
  final bool showPrice;

  const _CheckoutProductRow({
    required this.item,
    this.showPrice = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AppProductImage(
            imageUrl: item.product.imageUrl,
            height: 52,
            width: 52,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              if (item.variantLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.variantLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (showPrice) ...[
                const SizedBox(height: 3),
                Text(
                  formatRupiah(item.lineTotal),
                  style: NataloTextStyles.cartPrice.copyWith(
                    // Adaptif dark: priceText invisible di surface gelap.
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Qty ${item.quantity}',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckoutProductsSheet extends StatelessWidget {
  final List<CartItem> items;

  const _CheckoutProductsSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, controller) {
          final cs = Theme.of(context).colorScheme;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Produk dalam pesanan',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.outlineVariant
                    : const Color(0xFFE8EEF7),
              ),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    return _CheckoutProductRow(
                      item: items[index],
                      showPrice: true,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CheckoutNoteTile extends StatelessWidget {
  final String note;
  final VoidCallback onTap;

  const _CheckoutNoteTile({
    required this.note,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasNote = note.trim().isNotEmpty;
    return _CheckoutCardShell(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const _CheckoutSectionIcon(
            icon: Icons.edit_note_rounded,
            background: Color(0xFFF1F7FF),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catatan',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (hasNote) ...[
                  const SizedBox(height: 2),
                  Text(
                    note.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _CheckoutNoteSheet extends StatelessWidget {
  final TextEditingController controller;

  const _CheckoutNoteSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catatan',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Contoh: packing rapi ya admin.',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? cs.outlineVariant
                          : const Color(0xFFE8EEF7),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? cs.outlineVariant
                          : const Color(0xFFE8EEF7),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _brandBlue, width: 1.3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('Simpan Catatan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutShippingMethodCard extends StatelessWidget {
  final List<ShippingRate> rates;
  final ShippingRate selected;
  final bool hasSelection;
  final bool loading;
  final String? message;
  final VoidCallback onOpenMaps;
  final VoidCallback onTap;

  const _CheckoutShippingMethodCard({
    required this.rates,
    required this.selected,
    required this.hasSelection,
    required this.loading,
    required this.message,
    required this.onOpenMaps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canChange = !loading && rates.isNotEmpty;
    return _CheckoutCardShell(
      onTap: canChange ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              hasSelection
                  ? _ShippingMethodIcon(rate: selected, size: 42)
                  : const _CheckoutSectionIcon(
                      icon: Icons.local_shipping_rounded,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSelection && selected.isSelfPickup
                          ? 'Metode Pengambilan'
                          : 'Metode Pengiriman',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasSelection ? selected.label : 'Pilih metode pengiriman',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      !hasSelection
                          ? 'Pilih kurir atau ambil sendiri sebelum buat pesanan'
                          : selected.isSelfPickup
                              ? 'Self Pick Up - Gratis Ongkir'
                              : selected.price == 0
                                  ? 'Gratis'
                                  : formatRupiah(selected.price),
                      style: TextStyle(
                        color: !hasSelection
                            ? cs.onSurfaceVariant
                            : selected.price == 0
                                ? const Color(0xFF16A34A)
                                : cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (hasSelection &&
                        !selected.isSelfPickup &&
                        selected.duration.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        selected.duration,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (canChange)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ubah',
                      style: TextStyle(
                        color: _brandBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, color: _brandBlue),
                  ],
                ),
            ],
          ),
          if (hasSelection &&
              !selected.isSelfPickup &&
              message != null &&
              message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CheckoutInlineNotice(message: message!),
          ],
          if (hasSelection && selected.isSelfPickup) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? cs.outlineVariant
                      : const Color(0xFFE8EEF7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lokasi Toko',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${PickupStoreInfo.name}\n${PickupStoreInfo.address}',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onOpenMaps,
                    icon: const Icon(Icons.location_on_outlined, size: 18),
                    label: const Text('Buka di Google Maps'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brandBlue,
                      side: const BorderSide(color: _brandBlue, width: 1.2),
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckoutInlineNotice extends StatelessWidget {
  final String message;

  const _CheckoutInlineNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFF59E0B),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShippingMethodSheet extends StatelessWidget {
  final List<ShippingRate> rates;
  final ShippingRate selected;
  final bool hasSelection;
  final bool loading;
  final String? message;

  const _ShippingMethodSheet({
    required this.rates,
    required this.selected,
    required this.hasSelection,
    required this.loading,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupShippingRates(rates);
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.64,
        minChildSize: 0.42,
        maxChildSize: 0.9,
        builder: (context, controller) {
          final cs = Theme.of(context).colorScheme;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Metode Pengiriman',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const LinearProgressIndicator(minHeight: 2)
              else
                Divider(
                  height: 1,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? cs.outlineVariant
                      : const Color(0xFFE8EEF7),
                ),
              if (message != null && message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _CheckoutInlineNotice(message: message!),
                ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                  children: [
                    for (final group in groups) ...[
                      _ShippingRateGroupHeader(group: group),
                      const SizedBox(height: 8),
                      for (final rate in group.rates) ...[
                        _ShippingRateTile(
                          rate: rate,
                          active: hasSelection &&
                              rate.courierCode == selected.courierCode &&
                              rate.serviceCode == selected.serviceCode,
                          onTap: rate.available
                              ? () => Navigator.pop(context, rate)
                              : null,
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShippingRateGroup {
  final String title;
  final String hint;
  final String badge;
  final List<ShippingRate> rates;

  const _ShippingRateGroup({
    required this.title,
    required this.hint,
    required this.badge,
    required this.rates,
  });
}

List<_ShippingRateGroup> _groupShippingRates(List<ShippingRate> rates) {
  final pickupRates = <ShippingRate>[];
  final instantRates = <ShippingRate>[];
  final regularRates = <ShippingRate>[];
  final economyRates = <ShippingRate>[];
  final otherRates = <ShippingRate>[];

  for (final rate in rates) {
    if (rate.isSelfPickup) {
      pickupRates.add(rate);
    } else if (_isInstantShippingRate(rate)) {
      instantRates.add(rate);
    } else if (_isEconomyShippingRate(rate)) {
      economyRates.add(rate);
    } else if (_isRegularShippingRate(rate)) {
      regularRates.add(rate);
    } else {
      otherRates.add(rate);
    }
  }

  return [
    if (pickupRates.isNotEmpty)
      _ShippingRateGroup(
        title: 'Ambil Sendiri',
        hint: 'Gratis ongkir',
        badge: 'SHOP',
        rates: pickupRates,
      ),
    if (instantRates.isNotEmpty)
      _ShippingRateGroup(
        title: 'Instant',
        hint: 'Gojek / Grab, estimasi hari ini',
        badge: 'INST',
        rates: instantRates,
      ),
    if (regularRates.isNotEmpty)
      _ShippingRateGroup(
        title: 'Reguler',
        hint: 'Estimasi 1-3 hari',
        badge: 'REG',
        rates: regularRates,
      ),
    if (economyRates.isNotEmpty)
      _ShippingRateGroup(
        title: 'Ekonomi',
        hint: 'Estimasi hemat',
        badge: 'ECO',
        rates: economyRates,
      ),
    if (otherRates.isNotEmpty)
      _ShippingRateGroup(
        title: 'Lainnya',
        hint: 'Pilihan pengiriman tersedia',
        badge: 'OPS',
        rates: otherRates,
      ),
  ];
}

bool _isInstantShippingRate(ShippingRate rate) {
  final haystack = _shippingRateSearchText(rate);
  return haystack.contains('instant') ||
      haystack.contains('same_day') ||
      haystack.contains('sameday') ||
      haystack.contains('same day') ||
      haystack.contains('gosend') ||
      haystack.contains('go send') ||
      haystack.contains('gojek') ||
      haystack.contains('grab');
}

bool _isRegularShippingRate(ShippingRate rate) {
  final haystack = _shippingRateSearchText(rate);
  return haystack.contains('regular') ||
      haystack.contains('reguler') ||
      haystack.contains('next_day') ||
      haystack.contains('next day') ||
      haystack.contains('jne') ||
      haystack.contains('jnt') ||
      haystack.contains('j&t');
}

bool _isEconomyShippingRate(ShippingRate rate) {
  final haystack = _shippingRateSearchText(rate);
  return haystack.contains('economy') ||
      haystack.contains('ekonomi') ||
      haystack.contains('cargo') ||
      haystack.contains('trucking') ||
      haystack.contains('jtr');
}

String _shippingRateSearchText(ShippingRate rate) {
  return '${rate.courierCode} ${rate.courierName} ${rate.serviceCode} '
          '${rate.serviceName} ${rate.serviceType} ${rate.duration}'
      .toLowerCase();
}

class _ShippingRateGroupHeader extends StatelessWidget {
  final _ShippingRateGroup group;

  const _ShippingRateGroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                : const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            group.badge,
            style: const TextStyle(
              color: _brandBlue,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          group.title,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            group.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShippingRateTile extends StatelessWidget {
  final ShippingRate rate;
  final bool active;
  final VoidCallback? onTap;

  const _ShippingRateTile({
    required this.rate,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = onTap == null;
    return Material(
      color: active
          ? (isDark
              ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
              : const Color(0xFFEAF5FF))
          : cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? _brandBlue
                  : (Theme.of(context).brightness == Brightness.dark
                      ? cs.outlineVariant
                      : const Color(0xFFE8EEF7)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: active
                    ? _brandBlue
                    : disabled
                        ? cs.outlineVariant
                        : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              _ShippingMethodIcon(rate: rate, disabled: disabled, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rate.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: disabled ? cs.onSurfaceVariant : cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rate.isSelfPickup
                          ? PickupStoreInfo.address
                          : disabled
                              ? rate.unavailableReason ?? 'Tidak tersedia'
                              : rate.duration,
                      maxLines: rate.isSelfPickup ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rate.price == 0 ? 'Gratis' : formatRupiah(rate.price),
                style: TextStyle(
                  color: disabled
                      ? cs.onSurfaceVariant
                      : rate.price == 0
                          ? const Color(0xFF16A34A)
                          : cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutPaymentMethodCard extends StatelessWidget {
  final String payment;
  final VoidCallback onTap;

  const _CheckoutPaymentMethodCard({
    required this.payment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = payment == 'Midtrans'
        ? 'QRIS, Virtual Account, E-wallet'
        : 'Konfirmasi pembayaran setelah transfer';
    return _CheckoutCardShell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CheckoutSectionIcon(
              icon: Icons.account_balance_wallet_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Metode Pembayaran',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  payment,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ubah',
                style: TextStyle(
                  color: _brandBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: _brandBlue),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodSheet extends StatelessWidget {
  final String selected;

  const _PaymentMethodSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const options = ['Transfer Manual', 'Midtrans'];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Metode Pembayaran',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            ...options.map((option) {
              final active = option == selected;
              final subtitle = option == 'Midtrans'
                  ? 'QRIS, Virtual Account, E-wallet'
                  : 'Konfirmasi pembayaran setelah transfer';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PaymentMethodTile(
                  option: option,
                  subtitle: subtitle,
                  active: active,
                  onTap: () => Navigator.pop(context, option),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final String option;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.option,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: active
          ? (isDark
              ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
              : const Color(0xFFEAF5FF))
          : cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? _brandBlue
                  : (Theme.of(context).brightness == Brightness.dark
                      ? cs.outlineVariant
                      : const Color(0xFFE8EEF7)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: active ? _brandBlue : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              const _CheckoutSectionIcon(icon: Icons.credit_card_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card "Saldo Refund Tersedia" di checkout — toggle untuk pakai/skip
/// saldo refund sebagai pengurang sisa bayar.
///
/// Visual:
///  - Icon wallet biru + label "Saldo Refund"
///  - Available balance (font besar)
///  - Subtitle "Tersedia untuk pesanan ini"
///  - Switch toggle (kanan)
///  - Saat ON + used > 0: section "Digunakan -Rp{used}" tampil
///
/// Default ON (per UX best practice) — saldo refund yang available
/// langsung dipakai. User bisa toggle OFF kalau mau saving untuk
/// pesanan lain.
class _RefundBalanceCard extends StatelessWidget {
  final double available;
  final double used;
  final bool enabled;
  final bool syncing;
  final ValueChanged<bool> onChanged;

  const _RefundBalanceCard({
    required this.available,
    required this.used,
    required this.enabled,
    required this.syncing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CheckoutCardShell(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: _brandBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo Refund',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tersedia ${formatRupiah(available)}',
                  style: const TextStyle(
                    color: _brandBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (enabled && used > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Digunakan -${formatRupiah(used)}',
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: syncing ? null : onChanged,
            activeTrackColor: _brandBlue,
          ),
        ],
      ),
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  final double subtotal;
  final double shippingBaseCost;
  final double shippingCost;
  final double productDiscount;
  final double shippingDiscount;
  final double refundBalanceUsed;
  final double grandTotal;
  final bool syncing;
  final bool syncRetrying;
  final bool syncFailed;
  final String? syncError;
  final VoidCallback? onRetrySync;

  const _PaymentSummaryCard({
    required this.subtotal,
    required this.shippingBaseCost,
    required this.shippingCost,
    required this.productDiscount,
    required this.shippingDiscount,
    required this.grandTotal,
    this.refundBalanceUsed = 0,
    this.syncing = false,
    this.syncRetrying = false,
    this.syncFailed = false,
    this.syncError,
    this.onRetrySync,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CheckoutCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CheckoutSectionIcon(icon: Icons.receipt_long_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rincian Pembayaran',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (syncing || syncRetrying)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (syncRetrying)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Menyinkronkan ulang total checkout...',
                style: TextStyle(
                  color: _brandBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (syncFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total checkout belum tersinkron. Cek koneksi lalu coba lagi.',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((syncError ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      syncError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: syncing ? null : onRetrySync,
                      style: TextButton.styleFrom(
                        foregroundColor: _brandBlue,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text(
                        'Coba sinkronkan lagi',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _SummaryLine(label: 'Subtotal produk', value: formatRupiah(subtotal)),
          _SummaryLine(
            label: 'Total Ongkos Kirim',
            value: shippingBaseCost == 0
                ? 'Gratis'
                : formatRupiah(shippingBaseCost),
            freeShipping: shippingBaseCost == 0,
          ),
          if (productDiscount > 0)
            _SummaryLine(
              label: 'Diskon Produk',
              value: '-${formatRupiah(productDiscount)}',
              discount: true,
            ),
          if (shippingDiscount > 0)
            _SummaryLine(
              label: 'Diskon Ongkos Kirim',
              value: '-${formatRupiah(shippingDiscount)}',
              freeShipping: true,
            ),
          if (shippingBaseCost > 0 && shippingCost != shippingBaseCost)
            _SummaryLine(
              label: 'Ongkir setelah diskon',
              value: shippingCost == 0 ? 'Gratis' : formatRupiah(shippingCost),
              freeShipping: shippingCost == 0,
            ),
          if (refundBalanceUsed > 0)
            _SummaryLine(
              label: 'Saldo Refund Digunakan',
              value: '-${formatRupiah(refundBalanceUsed)}',
              discount: true,
            ),
          const Divider(height: 24),
          _SummaryLine(
            label: 'Total Bayar',
            value: formatRupiah(grandTotal),
            strong: true,
          ),
          // Poin yang akan didapat — earn formula mirror backend
          // (/api/orders/route.ts): floor(total / 20000). Sebelumnya cuma
          // muncul di dialog back-to-cart; di ringkasan utama bikin user
          // sadar benefit loyalty sebelum bayar (perceived value).
          if ((grandTotal / 20000).floor() > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.monetization_on_rounded,
                    size: 16, color: Color(0xFFE0A52E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Kamu akan dapat ${(grandTotal / 20000).floor()} poin',
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Trust badge — sinyal keamanan pembayaran (standar e-commerce).
          Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pembayaran aman & terenkripsi.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutSavingsStrip extends StatefulWidget {
  final double productDiscount;
  final double shippingDiscount;

  const _CheckoutSavingsStrip({
    required this.productDiscount,
    required this.shippingDiscount,
  });

  @override
  State<_CheckoutSavingsStrip> createState() => _CheckoutSavingsStripState();
}

class _CheckoutSavingsStripState extends State<_CheckoutSavingsStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final productDiscount = widget.productDiscount;
    final shippingDiscount = widget.shippingDiscount;
    final totalSavings = productDiscount + shippingDiscount;
    if (totalSavings <= 0) return const SizedBox.shrink();

    final hasProduct = productDiscount > 0;
    final hasShipping = shippingDiscount > 0;
    final title = _savingsTitle(productDiscount, shippingDiscount);
    final subtitle = hasProduct && hasShipping
        ? 'Diskon produk & ongkir sudah diterapkan'
        : hasProduct
            ? 'Diskon produk sudah diterapkan'
            : 'Diskon ongkir sudah diterapkan';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: const Color(0xFFFFF1F3),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            AppHaptics.tap();
            setState(() => _expanded = !_expanded);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFCDD6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 34,
                      width: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_offer_rounded,
                        color: Color(0xFFE91E63),
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFFE91E63),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFF9F1239),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFE91E63),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            const Text(
                              'Rincian Hemat',
                              style: TextStyle(
                                color: Color(0xFF17202A),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (hasProduct)
                              _SavingsDetailLine(
                                label: 'Diskon Produk',
                                value: '-${formatRupiah(productDiscount)}',
                                valueColor: NataloColors.discountRed,
                              ),
                            if (hasShipping)
                              _SavingsDetailLine(
                                label: 'Diskon Ongkos Kirim',
                                value: '-${formatRupiah(shippingDiscount)}',
                                valueColor: NataloColors.successGreen,
                              ),
                            const Divider(height: 20, color: Color(0xFFFFCDD6)),
                            _SavingsDetailLine(
                              label: 'Total Hemat',
                              value: formatRupiah(totalSavings),
                              valueColor: const Color(0xFFE91E63),
                              strong: true,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavingsDetailLine extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool strong;

  const _SavingsDetailLine({
    required this.label,
    required this.value,
    required this.valueColor,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong
                    ? NataloColors.textPrimary
                    : NataloColors.textSecondary,
                fontSize: strong ? 13.5 : 12.5,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: strong ? 14.5 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _savingsTitle(double productDiscount, double shippingDiscount) {
  final totalSavings = productDiscount + shippingDiscount;
  if (totalSavings <= 0) return '';
  if (productDiscount > 0 && shippingDiscount > 0) {
    return 'Total Hemat ${formatRupiah(totalSavings)} di pesanan ini';
  }
  if (productDiscount > 0) {
    return 'Total Hemat ${formatRupiah(productDiscount)} di pesanan ini';
  }
  return 'Total Hemat Ongkir ${formatRupiah(shippingDiscount)} di pesanan ini';
}

String _savingsCompactLabel(double productDiscount, double shippingDiscount) {
  final totalSavings = productDiscount + shippingDiscount;
  if (totalSavings <= 0) return '';
  if (productDiscount <= 0 && shippingDiscount > 0) {
    return 'Total Hemat Ongkir ${formatRupiah(shippingDiscount)}';
  }
  return 'Total Hemat ${formatRupiah(totalSavings)}';
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final bool discount;
  final bool freeShipping;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.strong = false,
    this.discount = false,
    this.freeShipping = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final valueColor = strong
        ? cs.onSurface
        : discount
            ? const Color(0xFFE91E63)
            : freeShipping
                ? const Color(0xFF16A34A)
                : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w900,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutBottomBar extends StatelessWidget {
  final double total;
  final double productDiscount;
  final double shippingDiscount;
  final VoidCallback onPressed;
  final bool submitting;
  final bool disabled;
  final bool visible;

  const _CheckoutBottomBar({
    required this.total,
    required this.productDiscount,
    required this.shippingDiscount,
    required this.onPressed,
    required this.submitting,
    this.disabled = false,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalSavings = productDiscount + shippingDiscount;
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: AppGlassBottomBar(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Bayar',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        formatRupiah(total),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (totalSavings > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          _savingsCompactLabel(
                            productDiscount,
                            shippingDiscount,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE91E63),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: submitting || disabled ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(150, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Buat Pesanan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckoutFinalPaymentPanel extends StatelessWidget {
  final double total;
  final VoidCallback onPressed;
  final bool submitting;
  final bool disabled;

  const _CheckoutFinalPaymentPanel({
    required this.total,
    required this.onPressed,
    required this.submitting,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CheckoutCardShell(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            'Total Bayar',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatRupiah(total),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: submitting || disabled ? null : onPressed,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Buat Pesanan'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCheckoutState extends StatelessWidget {
  const _EmptyCheckoutState();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      lottiePath: AppLottiePaths.empty,
      title: 'Checkout belum siap',
      subtitle: 'Belum ada item untuk checkout.',
      action: ElevatedButton(
        onPressed: () => Navigator.pushReplacementNamed(context, '/products'),
        child: const Text('Pilih Produk'),
      ),
    );
  }
}

class _VoucherSlot extends StatefulWidget {
  final MemberVoucher? freeShippingVoucher;
  final MemberVoucher? productVoucher;
  final MemberVoucher? loyaltyVoucher;
  final MemberVoucher? manualSelected;
  final List<MemberVoucher> availableVouchers;
  final List<MemberVoucher> unavailableVouchers;
  final bool loading;
  final VoidCallback onViewVouchers;
  final ValueChanged<String> onApplyManualCode;

  const _VoucherSlot({
    required this.freeShippingVoucher,
    required this.productVoucher,
    required this.loyaltyVoucher,
    required this.manualSelected,
    required this.availableVouchers,
    required this.unavailableVouchers,
    required this.loading,
    required this.onViewVouchers,
    required this.onApplyManualCode,
  });

  @override
  State<_VoucherSlot> createState() => _VoucherSlotState();
}

class _VoucherSlotState extends State<_VoucherSlot> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _voucherManualCodeText(widget.manualSelected),
    );
  }

  @override
  void didUpdateWidget(covariant _VoucherSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextCode = _voucherManualCodeText(widget.manualSelected);
    if (oldWidget.manualSelected?.code != widget.manualSelected?.code &&
        _controller.text.trim() != nextCode) {
      _controller.text = nextCode;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = [
      widget.freeShippingVoucher,
      widget.productVoucher,
      widget.loyaltyVoucher,
      widget.manualSelected,
    ].whereType<MemberVoucher>().toList();
    final hasSelected = selected.isNotEmpty;
    final selectedCount = selected.length;
    final hasShippingVoucher = selected.any(
      (voucher) => voucher.isFreeShipping || voucher.isShippingDiscount,
    );
    final productDiscount = selected
        .where(
          (voucher) => !(voucher.isFreeShipping || voucher.isShippingDiscount),
        )
        .fold<int>(0, (sum, voucher) => sum + voucher.discount);
    final fallbackDiscount = selected.fold<int>(
      0,
      (sum, voucher) => sum + voucher.discount,
    );
    final discountChipAmount =
        productDiscount > 0 ? productDiscount : fallbackDiscount;
    final totalKnownVouchers = _dedupeVouchers([
      ...selected,
      ...widget.availableVouchers,
      ...widget.unavailableVouchers,
    ]).length;
    final emptyChipLabel = totalKnownVouchers > 0
        ? '$totalKnownVouchers tersedia'
        : 'Lihat voucher';
    final cs = Theme.of(context).colorScheme;

    return _CheckoutCardShell(
      onTap: null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CheckoutSectionIcon(
                icon: Icons.confirmation_number_rounded,
                color: hasSelected ? const Color(0xFFE91E63) : _brandBlue,
                background: hasSelected
                    ? const Color(0xFFFFE8EF)
                    : const Color(0xFFEAF3FF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: widget.onViewVouchers,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          'Voucher',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                if (widget.loading) ...[
                                  SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (hasSelected) ...[
                                  if (hasShippingVoucher)
                                    const _VoucherSummaryChip(
                                      label: 'Gratis Ongkir',
                                      color: Color(0xFF12A66A),
                                      background: Color(0xFFEAFBF2),
                                      border: Color(0xFFB7EFD2),
                                    ),
                                  if (hasShippingVoucher &&
                                      discountChipAmount > 0)
                                    const SizedBox(width: 8),
                                  if (discountChipAmount > 0)
                                    _VoucherSummaryChip(
                                      label:
                                          '-${formatRupiah(discountChipAmount.toDouble())}',
                                      color: const Color(0xFFE91E63),
                                      background: const Color(0xFFFFE8EF),
                                      border: const Color(0xFFF8BBD0),
                                    ),
                                  if (!hasShippingVoucher &&
                                      discountChipAmount <= 0)
                                    _VoucherSummaryChip(
                                      label: selectedCount > 1
                                          ? '$selectedCount voucher'
                                          : _voucherTypeLabel(selected.first),
                                      color: const Color(0xFFE91E63),
                                      background: const Color(0xFFFFE8EF),
                                      border: const Color(0xFFF8BBD0),
                                    ),
                                ] else
                                  _VoucherSummaryChip(
                                    label: emptyChipLabel,
                                    color: cs.onSurfaceVariant,
                                    background: cs.surfaceContainerHighest,
                                    border: cs.outlineVariant,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: hasSelected
                              ? const Color(0xFFE91E63)
                              : cs.onSurfaceVariant,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ManualVoucherCodeField(
            controller: _controller,
            loading: widget.loading,
            onApply: () => widget.onApplyManualCode(_controller.text),
            onClear: () {
              _controller.clear();
              widget.onApplyManualCode('');
            },
          ),
        ],
      ),
    );
  }
}

class _VoucherSummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final Color border;

  const _VoucherSummaryChip({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

bool _voucherTextLooksLikeUrl(String value) {
  final text = value.trim().toLowerCase();
  if (text.isEmpty) return false;
  return text.startsWith('http://') ||
      text.startsWith('https://') ||
      text.startsWith('www.') ||
      text.contains('://') ||
      text.contains('www.natalopetshop.com') ||
      text.contains('natalopetshop.com/');
}

String _voucherManualCodeText(MemberVoucher? voucher) {
  final code = voucher?.code.trim() ?? '';
  return _voucherTextLooksLikeUrl(code) ? '' : code;
}

String _voucherAppliedSubtitle(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Diskon ongkir sudah diterapkan';
  }
  if (voucher.isLoyaltyClaim) {
    return 'Reward poin sudah diterapkan';
  }
  if (voucher.isPrivateManual) {
    return 'Kode khusus sudah diterapkan';
  }
  return 'Diskon produk sudah diterapkan';
}

String _voucherTypeLabel(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    final brand = voucher.brandName?.trim();
    if (voucher.isBrandExclusive && brand != null && brand.isNotEmpty) {
      return 'Gratis Ongkir dari $brand';
    }
    return 'Voucher Gratis Ongkir';
  }
  if (voucher.isLoyaltyClaim) {
    return 'Voucher Reward Poin';
  }
  if (voucher.isPrivateManual) {
    return 'Voucher Kode Khusus';
  }
  return 'Voucher Diskon Produk';
}

String _voucherDescriptionText(MemberVoucher voucher) {
  final description = voucher.description.trim();
  if (description.isNotEmpty && !_voucherTextLooksLikeUrl(description)) {
    return description;
  }
  if (voucher.minimumOrder > 0) {
    return 'Minimal belanja ${formatRupiah(voucher.minimumOrder.toDouble())}.';
  }
  return voucher.applicable
      ? 'Voucher bisa digunakan untuk pesanan ini.'
      : 'Voucher belum memenuhi syarat.';
}

String _voucherSavingsText(MemberVoucher voucher) {
  if (voucher.discount > 0) {
    return 'Hemat ${formatRupiah(voucher.discount.toDouble())}';
  }
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Gratis Ongkir';
  }
  return voucher.applicable ? 'Bisa dipakai' : 'Tidak tersedia';
}

String _voucherDiscountAmountText(MemberVoucher voucher) {
  if (voucher.discount <= 0) {
    if (voucher.isFreeShipping || voucher.isShippingDiscount) {
      return 'Gratis Ongkir';
    }
    return voucher.applicable ? 'Aktif' : 'Tidak tersedia';
  }
  return '-${formatRupiah(voucher.discount.toDouble())}';
}

Color _voucherAccentColor(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return const Color(0xFF12A66A);
  }
  if (voucher.isBrandExclusive) return NataloColors.brandExclusiveDark;
  if (voucher.isLoyaltyClaim) return const Color(0xFF7C3AED);
  return const Color(0xFFE91E63);
}

IconData _voucherIcon(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return Icons.local_shipping_outlined;
  }
  if (voucher.isBrandExclusive) return Icons.workspace_premium_rounded;
  if (voucher.isLoyaltyClaim) return Icons.stars_rounded;
  if (voucher.isPrivateManual) return Icons.confirmation_number_outlined;
  return Icons.sell_outlined;
}

List<MemberVoucher> _dedupeVouchers(Iterable<MemberVoucher> vouchers) {
  final seen = <String>{};
  final result = <MemberVoucher>[];
  for (final voucher in vouchers) {
    final key = [
      voucher.type,
      voucher.code,
      voucher.title,
      voucher.discountScope,
    ].join('|');
    if (seen.add(key)) result.add(voucher);
  }
  return result;
}

bool _sameVoucher(MemberVoucher a, MemberVoucher b) {
  if (a.code.isNotEmpty && b.code.isNotEmpty) {
    return a.code == b.code && a.type == b.type;
  }
  return a.type == b.type &&
      a.title == b.title &&
      a.discount == b.discount &&
      a.discountScope == b.discountScope;
}

class _CheckoutVoucherDetailsSheet extends StatelessWidget {
  final List<MemberVoucher> selected;
  final List<MemberVoucher> available;
  final List<MemberVoucher> unavailable;
  final bool loading;
  final ValueChanged<MemberVoucher> onApply;
  final ValueChanged<MemberVoucher> onRemove;

  const _CheckoutVoucherDetailsSheet({
    required this.selected,
    required this.available,
    required this.unavailable,
    required this.loading,
    required this.onApply,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final selectedClean = _dedupeVouchers(selected);
    final availableClean = _dedupeVouchers(available);
    final unavailableClean = _dedupeVouchers(unavailable);
    final otherAvailable = availableClean
        .where(
          (voucher) =>
              !selectedClean.any((selected) => _sameVoucher(selected, voucher)),
        )
        .toList();
    final hasAny = selectedClean.isNotEmpty ||
        otherAvailable.isNotEmpty ||
        unavailableClean.isNotEmpty;

    // WAJIB: safe-area inset dipindah ke padding bawah ListView (di bawah),
    // JANGAN bungkus SafeArea di sini. Kalau SafeArea(top:false) membungkus
    // Container background putih ini, celah safe-area di bawah jadi
    // transparan — menampakkan scrim gelap modal barrier di baliknya
    // (strip abu-abu di tepi bawah sheet). Sama persis bug yang pernah
    // ditemukan & diperbaiki di voucher sheet product_detail_screen.dart.
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.46,
      maxChildSize: 0.92,
      builder: (context, controller) {
        final cs = Theme.of(context).colorScheme;
        final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                height: 5,
                width: 44,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Voucher Natalo',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Cek voucher yang dipakai otomatis dan voucher lain.',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              Divider(
                height: 1,
                color: Theme.of(context).brightness == Brightness.dark
                    ? cs.outlineVariant
                    : const Color(0xFFE8EEF7),
              ),
              Expanded(
                child: hasAny
                    ? ListView(
                        controller: controller,
                        padding:
                            EdgeInsets.fromLTRB(20, 16, 20, 28 + bottomInset),
                        children: [
                          if (selectedClean.isNotEmpty) ...[
                            const _VoucherSheetSectionTitle(
                              'Terpakai otomatis',
                            ),
                            const SizedBox(height: 10),
                            _AppliedVoucherSummaryCard(
                              vouchers: selectedClean,
                              onRemove: (voucher) {
                                Navigator.pop(context);
                                onRemove(voucher);
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (otherAvailable.isNotEmpty) ...[
                            const _VoucherSheetSectionTitle(
                              'Voucher tersedia',
                            ),
                            const SizedBox(height: 10),
                            ...otherAvailable.map(
                              (voucher) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _VoucherDetailTile(
                                  voucher: voucher,
                                  onApply: () {
                                    Navigator.pop(context);
                                    onApply(voucher);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (unavailableClean.isNotEmpty) ...[
                            const _VoucherSheetSectionTitle(
                              'Belum memenuhi syarat',
                            ),
                            const SizedBox(height: 10),
                            ...unavailableClean.map(
                              (voucher) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _VoucherDetailTile(
                                  voucher: voucher,
                                  enabled: false,
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    : const _VoucherEmptyState(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoucherSheetSectionTitle extends StatelessWidget {
  final String text;

  const _VoucherSheetSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _AppliedVoucherSummaryCard extends StatelessWidget {
  final List<MemberVoucher> vouchers;
  final ValueChanged<MemberVoucher> onRemove;

  const _AppliedVoucherSummaryCard({
    required this.vouchers,
    required this.onRemove,
  });

  /// Defensive dedup by business-type. Per business rule Natalo: max 1
  /// voucher per type (gratis ongkir / diskon produk / reward poin /
  /// manual code). Caller layer (_syncCheckoutPricing) sudah dedup slot,
  /// tapi second-layer guard di sini supaya kalau ada source lain yang
  /// inject duplicate (mis. legacy code path), display tetap show 1 per
  /// type. Keep first occurrence per type, drop sisanya.
  static List<MemberVoucher> _dedupeByType(List<MemberVoucher> input) {
    final result = <MemberVoucher>[];
    bool hasShipping = false;
    bool hasProduct = false;
    bool hasLoyalty = false;
    bool hasManual = false;
    for (final v in input) {
      if (v.isFreeShipping || v.isShippingDiscount) {
        if (hasShipping) continue;
        hasShipping = true;
      } else if (v.isLoyaltyClaim) {
        if (hasLoyalty) continue;
        hasLoyalty = true;
      } else if (v.isPrivateManual) {
        if (hasManual) continue;
        hasManual = true;
      } else {
        // Default = product discount.
        if (hasProduct) continue;
        hasProduct = true;
      }
      result.add(v);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final deduped = _dedupeByType(vouchers);
    final totalSavings = deduped.fold<int>(
      0,
      (sum, voucher) => sum + voucher.discount,
    );
    const primary = Color(0xFFE91E63);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF9A8D4), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.confirmation_number_rounded,
                  color: Color(0xFFE91E63),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${deduped.length} voucher terpakai',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      totalSavings > 0
                          ? 'Total hemat ${formatRupiah(totalSavings.toDouble())}'
                          : 'Voucher aktif untuk pesanan ini',
                      style: const TextStyle(
                        color: primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFFE91E63),
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...deduped.map(
            (voucher) {
              final isLast = voucher == deduped.last;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                child: _AppliedVoucherLine(
                  voucher: voucher,
                  onRemove: () => onRemove(voucher),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppliedVoucherLine extends StatelessWidget {
  final MemberVoucher voucher;
  final VoidCallback onRemove;

  const _AppliedVoucherLine({
    required this.voucher,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _voucherAccentColor(voucher);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
      ),
      child: Row(
        children: [
          Container(
            height: 28,
            width: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_voucherIcon(voucher), color: accent, size: 16),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _voucherTypeLabel(voucher),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _voucherAppliedSubtitle(voucher),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _voucherDiscountAmountText(voucher),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _VoucherActionPill(
            label: 'Lepas',
            color: const Color(0xFFEF4444),
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _VoucherDetailTile extends StatelessWidget {
  final MemberVoucher voucher;
  final bool enabled;
  final VoidCallback? onApply;

  const _VoucherDetailTile({
    required this.voucher,
    this.enabled = true,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _voucherAccentColor(voucher);
    final foreground = enabled ? cs.onSurface : cs.onSurfaceVariant;
    final title = _voucherTypeLabel(voucher);
    final subtitle = voucher.disabledReason?.isNotEmpty == true
        ? voucher.disabledReason!
        : _voucherDescriptionText(voucher);

    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFE8EEF7),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_voucherIcon(voucher), color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (voucher.isBrandExclusive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF0DC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFCD9A0)),
                      ),
                      child: const Text(
                        'Brand Eksklusif',
                        style: TextStyle(
                          color: Color(0xFFB85C00),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (enabled)
                        _VoucherActionPill(
                          label: 'Pakai',
                          color: _brandBlue,
                          onTap: onApply,
                        )
                      else
                        Text(
                          _voucherSavingsText(voucher),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          enabled ? cs.onSurfaceVariant : cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (voucher.discount > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      _voucherSavingsText(voucher),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? accent : cs.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoucherActionPill extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _VoucherActionPill({
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _VoucherEmptyState extends StatelessWidget {
  const _VoucherEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Belum ada voucher yang bisa digunakan untuk pesanan ini.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ManualVoucherCodeField extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _ManualVoucherCodeField({
    required this.controller,
    required this.loading,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => onApply(),
      decoration: InputDecoration(
        hintText: 'Kode Manual',
        hintStyle: TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: const Icon(
          Icons.confirmation_number_outlined,
          color: _brandBlue,
        ),
        suffixIcon: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final hasText = controller.text.trim().isNotEmpty;
            if (loading) {
              return const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasText)
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Hapus kode',
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: hasText ? onApply : null,
                    child: const Text('Pakai'),
                  ),
                ),
              ],
            );
          },
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFE8EEF7),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFE8EEF7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _brandBlue, width: 1.3),
        ),
      ),
    );
  }
}
