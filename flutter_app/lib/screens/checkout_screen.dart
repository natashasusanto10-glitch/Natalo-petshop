import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cart_item.dart';
import '../models/member_address.dart';
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
import '../utils/app_review.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../utils/in_app_browser.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/order_success_overlay.dart';

const _brandBlue = NataloColors.nataloBlue;

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
  bool _autoVoucherSuppressed = false;
  CheckoutRecalcResult? _checkoutPricing;
  bool _isNearBottom = false;
  // Catatan pesanan ke admin.
  final TextEditingController _noteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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

  @override
  void dispose() {
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
    final courierRates =
        result.rates.where((rate) => !rate.isSelfPickup).toList();
    final rates = [ShippingRate.selfPickup, ...courierRates];
    final previousRate = _selectedRate;
    final selectedRate = rates.firstWhere(
      (rate) =>
          rate.courierCode == previousRate.courierCode &&
          rate.serviceCode == previousRate.serviceCode,
      orElse: () => rates.first,
    );
    setState(() {
      _shippingRates = rates;
      _selectedRate = selectedRate;
      _shippingMessage = result.instantUnavailableReason ?? result.message;
    });
  }

  void _selectAddress(MemberAddress address) {
    setState(() {
      _selectedAddress = address;
      _loadingRates = true;
    });
    _loadShippingRates().whenComplete(() {
      if (!mounted) return;
      setState(() => _loadingRates = false);
      _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
    });
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

  Future<void> _syncCheckoutPricing({required bool autoApply}) async {
    if (_checkoutItems.isEmpty) {
      if (!mounted) return;
      setState(() {
        _checkoutPricing = null;
        _selectedFreeShippingVoucher = null;
        _selectedProductVoucher = null;
        _selectedLoyaltyVoucher = null;
        _selectedManualVoucher = null;
        _availableVouchers = const [];
        _unavailableVouchers = const [];
        _voucherSyncFailed = false;
      });
      return;
    }

    setState(() {
      _syncingPricing = true;
      _loadingVouchers = true;
    });
    try {
      final recalc = await checkoutService.recalculate(
        items: _checkoutItemPayload(),
        shippingFee: _selectedRate.price,
        voucherCode: _selectedProductVoucher?.code,
        customerVoucherCode: _selectedProductVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
        freeShippingVoucherCode: _selectedFreeShippingVoucher?.code,
        productVoucherCode: _selectedProductVoucher?.code,
        loyaltyVoucherCode: _selectedLoyaltyVoucher?.code,
        privateVoucherCode: _selectedManualVoucher?.code,
        autoApply: autoApply,
        address: _selectedAddress,
        shippingRate: _selectedRate,
        paymentProvider: _paymentProvider,
      );
      if (!mounted || recalc == null) {
        if (mounted) {
          setState(() => _voucherSyncFailed = true);
        }
        return;
      }

      setState(() {
        _checkoutPricing = recalc;
        _voucherSyncFailed = false;
        _selectedFreeShippingVoucher = recalc.appliedFreeShippingVoucher;
        _selectedProductVoucher = recalc.appliedProductVoucher ??
            (recalc.appliedCustomerVoucher?.isProductDiscount == true
                ? recalc.appliedCustomerVoucher
                : null);
        _selectedLoyaltyVoucher = recalc.appliedLoyaltyVoucher ??
            (recalc.appliedCustomerVoucher?.isLoyaltyClaim == true
                ? recalc.appliedCustomerVoucher
                : null);
        _selectedManualVoucher =
            recalc.appliedPrivateVoucher ?? recalc.appliedManualVoucher;
        _availableVouchers = recalc.availableVouchers;
        _unavailableVouchers = recalc.unavailableVouchers;
      });
      final voucherError =
          recalc.manualVoucherError ?? recalc.customerVoucherError;
      if (voucherError != null && voucherError.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(voucherError),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _voucherSyncFailed = true);
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
      backgroundColor: Colors.white,
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
      backgroundColor: Colors.white,
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
      backgroundColor: Colors.white,
      builder: (context) => _ShippingMethodSheet(
        rates: _shippingRates,
        selected: _selectedRate,
        loading: _loadingRates,
        message: _shippingMessage,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedRate = picked);
    await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
  }

  Future<void> _openStoreMaps() async {
    AppHaptics.tap();
    final uri = Uri.parse(PickupStoreInfo.mapsUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tidak bisa membuka Google Maps.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openPaymentSheet() async {
    AppHaptics.tap();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _PaymentMethodSheet(selected: _payment),
    );
    if (!mounted || picked == null || picked == _payment) return;
    setState(() => _payment = picked);
    await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
  }

  Future<void> _placeOrder() async {
    setState(() => _submitting = true);
    try {
      final profile = memberStore.profile;
      final address = _selectedAddress;
      if (address == null) {
        throw Exception('Alamat pengiriman belum tersedia.');
      }
      // Step 1 — validate cart server-side. Catch stok kurang / harga
      // berubah SEBELUM hit createOrder (server tetap validate, tapi UX
      // lebih bagus kalau user dapat issue list dulu).
      final validation = await cartService.validate(_checkoutItems);
      if (!mounted) return;
      if (!validation.valid && validation.issues.isNotEmpty) {
        AppHaptics.warning();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Beberapa item perlu update: ${validation.issues.first.message}',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
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
        freeShippingVoucherCode: _selectedFreeShippingVoucher?.code,
        productVoucherCode: _selectedProductVoucher?.code,
        loyaltyVoucherCode: _selectedLoyaltyVoucher?.code,
        privateVoucherCode: _selectedManualVoucher?.code,
        autoApply: !_autoVoucherSuppressed,
        address: address,
        shippingRate: _selectedRate,
        paymentProvider: _paymentProvider,
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
        freeShippingVoucherCode: _selectedFreeShippingVoucher?.code,
        productVoucherCode: _selectedProductVoucher?.code,
        loyaltyVoucherCode: _selectedLoyaltyVoucher?.code,
        privateVoucherCode: _selectedManualVoucher?.code,
        notes: _noteController.text,
      );
      if (!mounted) return;
      // Midtrans flow — kalau payment provider MIDTRANS, server return URL
      // Snap dialog. Launch in-app browser supaya user tidak keluar app.
      if (_paymentProvider == 'MIDTRANS') {
        final token = await orderService.initiateMidtrans(
          orderNumber: result.orderNumber,
        );
        if (!mounted) return;
        if (token != null && token.redirectUrl.isNotEmpty) {
          await AppInAppBrowser.open(
            context,
            url: token.redirectUrl,
            title: 'Pembayaran Midtrans',
          );
        }
      }
      AppHaptics.success();
      // Analytics: conversion event utama — track purchase value + item count
      // untuk funnel + revenue dashboard. No-op kalau Firebase belum setup.
      AppAnalytics.logPurchase(
        transactionId: result.orderNumber,
        value: _grandTotal.round(),
      );
      // Confetti overlay 2.5s sebelum show order detail dialog.
      // Positive emotional moment — drive review / share / repeat purchase.
      if (!mounted) return;
      await showOrderSuccess(
        context,
        orderNumber: result.orderNumber,
        message:
            'Order ${result.orderNumber}\nKami segera memproses pesananmu.',
      );
      if (!mounted) return;
      await _showOrderSuccess(result);
      // Trigger in-app review prompt — best moment, user baru saja
      // menyelesaikan flow positif (order created). Cooldown 30 hari
      // handled di AppReview.maybeRequest().
      // ignore: use_build_context_synchronously
      AppReview.maybeRequest();
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checkout gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showOrderSuccess(OrderResult result) {
    final createdOrder = _createdOrderSummary(result);
    final hasPaymentLink = result.paymentUrl?.isNotEmpty ?? false;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return _CheckoutOrderSuccessDialog(
          orderNumber: result.orderNumber,
          message: result.message,
          hasPaymentLink: hasPaymentLink,
          onDone: () {
            cartStore.clear();
            Navigator.pop(context);
            Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
          },
          onOpenDetail: () => _openCreatedOrder(createdOrder),
          onPayNow: hasPaymentLink
              ? () => _openPaymentAndDetail(
                    result.paymentUrl!,
                    createdOrder,
                  )
              : null,
        );
      },
    );
  }

  OrderSummary _createdOrderSummary(OrderResult result) {
    return OrderSummary(
      id: result.orderNumber,
      orderNumber: result.orderNumber,
      status: 'PENDING',
      paymentStatus: _payment == 'Midtrans' ? 'PENDING' : 'PENDING',
      paymentProvider: _paymentProvider,
      paymentUrl: result.paymentUrl,
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
          price: item.product.finalPrice.round(),
          imageUrl: item.product.imageUrl,
          categoryName: item.product.category,
        );
      }).toList(),
    );
  }

  void _openCreatedOrder(OrderSummary order) {
    cartStore.clear();
    Navigator.pop(context);
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/member/order-detail',
      ModalRoute.withName('/'),
      arguments: order,
    );
  }

  Future<void> _openPaymentAndDetail(
    String paymentUrl,
    OrderSummary order,
  ) async {
    final uri = Uri.tryParse(paymentUrl);
    if (uri == null) {
      _showSnack('Link pembayaran tidak valid.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) {
      _showSnack('Tidak bisa membuka pembayaran.');
      return;
    }
    _openCreatedOrder(order);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cartStore,
      builder: (context, _) {
        if (_redirectingToLogin) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(
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
            backgroundColor: const Color(0xFFF6F9FF),
            appBar: AppBar(
              backgroundColor: const Color(0xFFF6F9FF),
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: const Color(0xFFF6F9FF),
              automaticallyImplyLeading: false,
              centerTitle: true,
              leading: IconButton(
                tooltip: 'Kembali',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF17202A),
                ),
                onPressed: () async {
                  AppHaptics.tap();
                  final shouldPop = await _confirmBackToCart(context);
                  if (shouldPop && context.mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
              title: const Text(
                'Checkout',
                style: TextStyle(
                  color: Color(0xFF17202A),
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
                        addresses: _addresses,
                        selected: _selectedAddress,
                        onChanged: _selectAddress,
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
                      const SizedBox(height: 12),
                      _PaymentSummaryCard(
                        subtotal: _itemsSubtotal,
                        shippingBaseCost: _shippingBaseCost,
                        shippingCost: _shippingCost,
                        productDiscount: _productDiscount,
                        shippingDiscount: _shippingDiscount,
                        grandTotal: _grandTotal,
                        syncing: _syncingPricing,
                        syncFailed: _voucherSyncFailed,
                      ),
                      _CheckoutSavingsStrip(
                        productDiscount: _productDiscount,
                        shippingDiscount: _shippingDiscount,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutFinalPaymentPanel(
                        total: _grandTotal,
                        submitting: _submitting,
                        disabled: _voucherSyncFailed || _syncingPricing,
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
                    disabled: _voucherSyncFailed || _syncingPricing,
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
    final hasActiveBenefit = voucherDiscount > 0;
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => _BackToCartDialog(
        showBenefits: hasActiveBenefit,
        voucherDiscount: voucherDiscount,
        shippingCost: _shippingCost,
        // Poin yang didapat = 1% dari subtotal (estimasi UX — match PWA pattern).
        estimatedPoints: (_itemsSubtotal / 1000).floor(),
      ),
    );
    return result == true;
  }
}

/// Modal "Voucher masih aktif" / "Yakin kembali ke keranjang" — match PWA
/// confirmation pop-up. Saat ada benefit aktif, tampilkan rincian yang
/// akan hilang. Saat tidak ada, konfirmasi ringan.
class _BackToCartDialog extends StatelessWidget {
  final bool showBenefits;
  final double voucherDiscount;
  final double shippingCost;
  final int estimatedPoints;

  const _BackToCartDialog({
    required this.showBenefits,
    required this.voucherDiscount,
    required this.shippingCost,
    required this.estimatedPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header icon
            if (showBenefits)
              Container(
                height: 72,
                width: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF5FF),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🎟️', style: TextStyle(fontSize: 36)),
              )
            else
              Container(
                height: 72,
                width: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF5FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: _brandBlue,
                  size: 34,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              showBenefits
                  ? 'Voucher kamu masih aktif!'
                  : 'Yakin kembali ke keranjang?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (showBenefits) ...[
              Text.rich(
                TextSpan(
                  text: 'Kamu sedang hemat ',
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.55,
                  ),
                  children: [
                    TextSpan(
                      text: formatRupiah(voucherDiscount),
                      style: const TextStyle(
                        color: NataloColors.discountRed,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const TextSpan(text: ' di checkout ini.\n'),
                    const TextSpan(
                      text: 'Lanjutkan pesanan agar voucher tidak terlewat.',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              // Benefits list — match screenshot persis
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    if (voucherDiscount > 0)
                      _BenefitRow(
                        emoji: '🎫',
                        label: 'Hemat Voucher',
                        value: formatRupiah(voucherDiscount),
                        valueColor: NataloColors.discountRed,
                      ),
                    if (shippingCost > 0) ...[
                      const SizedBox(height: 10),
                      _BenefitRow(
                        emoji: '🚚',
                        label: 'Ongkir',
                        value: formatRupiah(shippingCost),
                        valueColor: NataloColors.priceText,
                      ),
                    ],
                    if (estimatedPoints > 0) ...[
                      const SizedBox(height: 10),
                      _BenefitRow(
                        emoji: '🪙',
                        label: 'Poin yang didapat',
                        value: '$estimatedPoints poin',
                        valueColor: const Color(0xFFF59E0B),
                      ),
                    ],
                  ],
                ),
              ),
            ] else
              const Text(
                'Pesanan kamu belum selesai.\nKamu bisa lanjut checkout atau kembali mengatur keranjang.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
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
            const SizedBox(height: 8),
            // Secondary: Kembali ke Keranjang (return true → caller pop)
            OutlinedButton(
              onPressed: () {
                AppHaptics.tap();
                Navigator.pop(context, true);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: const Text('Kembali ke Keranjang'),
            ),
            // Close button top-right corner — match screenshot
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color valueColor;

  const _BenefitRow({
    required this.emoji,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF334155),
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
        color: Colors.white,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: const Color(0xFFE8EEF7)),
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
    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: background,
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
    final spec = _spec;
    final bg = disabled ? const Color(0xFFF2F4F7) : spec.background;
    final fg = disabled ? const Color(0xFF98A2B3) : spec.foreground;

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

class _CheckoutOrderSuccessDialog extends StatelessWidget {
  final String orderNumber;
  final String message;
  final bool hasPaymentLink;
  final VoidCallback onDone;
  final VoidCallback onOpenDetail;
  final VoidCallback? onPayNow;

  const _CheckoutOrderSuccessDialog({
    required this.orderNumber,
    required this.message,
    required this.hasPaymentLink,
    required this.onDone,
    required this.onOpenDetail,
    this.onPayNow,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 122,
                  height: 122,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF8EF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
                const AppLottieAsset(
                  asset: 'assets/lottie/order_created.json',
                  size: 150,
                  repeat: false,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Pesanan Dibuat',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF17202A),
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.42,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8EEF7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nomor order',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    orderNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (hasPaymentLink && onPayNow != null) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onPayNow,
                  child: const Text('Bayar Sekarang'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: onOpenDetail,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandBlue,
                  side: const BorderSide(color: _brandBlue, width: 1.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Lihat Detail'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onDone,
              child: const Text('Selesai'),
            ),
          ],
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
  final List<MemberAddress> addresses;
  final MemberAddress? selected;
  final ValueChanged<MemberAddress> onChanged;

  const _CheckoutAddressCard({
    required this.addresses,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _CheckoutCardShell(
      onTap: addresses.length <= 1 ? null : () => _showAddressSheet(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CheckoutSectionIcon(icon: Icons.location_on_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Alamat Pengiriman',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  selected?.recipient.isNotEmpty == true
                      ? selected!.recipient
                      : 'Alamat belum dipilih',
                  style: const TextStyle(
                    color: Color(0xFF17202A),
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
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (selected!.phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      selected!.phone,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Pilih alamat member untuk melanjutkan checkout.',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
        ],
      ),
    );
  }

  void _showAddressSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            itemCount: addresses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final address = addresses[index];
              final active = address.id == selected?.id;
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: active ? _brandBlue : const Color(0xFFE5E7EB),
                  ),
                ),
                leading: Icon(
                  active
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: active ? _brandBlue : const Color(0xFFE5E7EB),
                ),
                title: Text(address.label ?? 'Alamat'),
                subtitle: Text('${address.recipient} - ${address.address}'),
                onTap: () {
                  onChanged(address);
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
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
                    const Text(
                      'Ringkasan Produk dibeli',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalQty produk dalam pesanan',
                      style: const TextStyle(
                        color: Color(0xFF667085),
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
            const Divider(height: 1, color: Color(0xFFE8EEF7)),
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
                style: const TextStyle(
                  color: Color(0xFF17202A),
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
                  style: const TextStyle(
                    color: Color(0xFF667085),
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
            color: const Color(0xFFF2F6FC),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Qty ${item.quantity}',
            style: const TextStyle(
              color: Color(0xFF344054),
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
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Produk dalam pesanan',
                        style: TextStyle(
                          color: Color(0xFF17202A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE8EEF7)),
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
                const Text(
                  'Catatan',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (hasNote) ...[
                  const SizedBox(height: 2),
                  Text(
                    note.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
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
              const Text(
                'Catatan',
                style: TextStyle(
                  color: Color(0xFF17202A),
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
                  fillColor: const Color(0xFFF6F9FF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE8EEF7)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE8EEF7)),
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
  final bool loading;
  final String? message;
  final VoidCallback onOpenMaps;
  final VoidCallback onTap;

  const _CheckoutShippingMethodCard({
    required this.rates,
    required this.selected,
    required this.loading,
    required this.message,
    required this.onOpenMaps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canChange = !loading && rates.isNotEmpty;
    return _CheckoutCardShell(
      onTap: canChange ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShippingMethodIcon(rate: selected, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.isSelfPickup
                          ? 'Metode Pengambilan'
                          : 'Metode Pengiriman',
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selected.isSelfPickup
                          ? 'Self Pick Up - Gratis Ongkir'
                          : selected.price == 0
                              ? 'Gratis'
                              : formatRupiah(selected.price),
                      style: TextStyle(
                        color: selected.price == 0
                            ? const Color(0xFF16A34A)
                            : NataloColors.priceText,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selected.duration,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
          if (!selected.isSelfPickup &&
              message != null &&
              message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CheckoutInlineNotice(message: message!),
          ],
          if (selected.isSelfPickup) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8EEF7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lokasi Toko',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '${PickupStoreInfo.name}\n${PickupStoreInfo.address}',
                    style: TextStyle(
                      color: Color(0xFF17202A),
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
  final bool loading;
  final String? message;

  const _ShippingMethodSheet({
    required this.rates,
    required this.selected,
    required this.loading,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.64,
        minChildSize: 0.42,
        maxChildSize: 0.9,
        builder: (context, controller) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Metode Pengiriman',
                        style: TextStyle(
                          color: Color(0xFF17202A),
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
                const Divider(height: 1, color: Color(0xFFE8EEF7)),
              if (message != null && message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _CheckoutInlineNotice(message: message!),
                ),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                  itemCount: rates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final rate = rates[index];
                    final active = rate.courierCode == selected.courierCode &&
                        rate.serviceCode == selected.serviceCode;
                    return _ShippingRateTile(
                      rate: rate,
                      active: active,
                      onTap: rate.available
                          ? () => Navigator.pop(context, rate)
                          : null,
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
    final disabled = onTap == null;
    return Material(
      color: active ? const Color(0xFFEAF5FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? _brandBlue : const Color(0xFFE8EEF7),
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
                        ? const Color(0xFFD0D5DD)
                        : const Color(0xFF98A2B3),
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
                        color: disabled
                            ? const Color(0xFF98A2B3)
                            : const Color(0xFF17202A),
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
                      style: const TextStyle(
                        color: Color(0xFF667085),
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
                      ? const Color(0xFF98A2B3)
                      : rate.price == 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF17202A),
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
                const Text(
                  'Metode Pembayaran',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  payment,
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF667085),
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
    const options = ['Transfer Manual', 'Midtrans'];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Metode Pembayaran',
              style: TextStyle(
                color: Color(0xFF17202A),
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
    return Material(
      color: active ? const Color(0xFFEAF5FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? _brandBlue : const Color(0xFFE8EEF7),
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: active ? _brandBlue : const Color(0xFF98A2B3),
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
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
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

class _PaymentSummaryCard extends StatelessWidget {
  final double subtotal;
  final double shippingBaseCost;
  final double shippingCost;
  final double productDiscount;
  final double shippingDiscount;
  final double grandTotal;
  final bool syncing;
  final bool syncFailed;

  const _PaymentSummaryCard({
    required this.subtotal,
    required this.shippingBaseCost,
    required this.shippingCost,
    required this.productDiscount,
    required this.shippingDiscount,
    required this.grandTotal,
    this.syncing = false,
    this.syncFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    return _CheckoutCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _CheckoutSectionIcon(icon: Icons.receipt_long_rounded),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rincian Pembayaran',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (syncing)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (syncFailed)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Total checkout belum tersinkron. Cek koneksi lalu coba lagi.',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
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
          const Divider(height: 24),
          _SummaryLine(
            label: 'Total Bayar',
            value: formatRupiah(grandTotal),
            strong: true,
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
    return 'Kamu hemat ${formatRupiah(totalSavings)} di pesanan ini';
  }
  if (productDiscount > 0) {
    return 'Kamu hemat ${formatRupiah(productDiscount)} di pesanan ini';
  }
  return 'Kamu hemat ongkir ${formatRupiah(shippingDiscount)} di pesanan ini';
}

String _savingsCompactLabel(double productDiscount, double shippingDiscount) {
  final totalSavings = productDiscount + shippingDiscount;
  if (totalSavings <= 0) return '';
  if (productDiscount <= 0 && shippingDiscount > 0) {
    return 'Hemat ongkir ${formatRupiah(shippingDiscount)}';
  }
  return 'Kamu hemat ${formatRupiah(totalSavings)}';
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
    final valueColor = strong
        ? const Color(0xFF17202A)
        : discount
            ? const Color(0xFFE91E63)
            : freeShipping
                ? const Color(0xFF16A34A)
                : const Color(0xFF17202A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:
                    strong ? const Color(0xFF17202A) : const Color(0xFF6B7280),
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
                      const Text(
                        'Total Bayar',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        formatRupiah(total),
                        style: const TextStyle(
                          color: Color(0xFF17202A),
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
    return _CheckoutCardShell(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Text(
            'Total Bayar',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatRupiah(total),
            style: const TextStyle(
              color: Color(0xFF17202A),
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
    final selectedDiscount = selected
        .fold<int>(
          0,
          (sum, voucher) => sum + voucher.discount,
        )
        .toDouble();
    final totalKnownVouchers = _dedupeVouchers([
      ...selected,
      ...widget.availableVouchers,
      ...widget.unavailableVouchers,
    ]).length;
    final chipText = selectedDiscount > 0
        ? 'Hemat ${formatRupiah(selectedDiscount)}'
        : selectedCount > 1
            ? '$selectedCount voucher'
            : selected.isNotEmpty
                ? _voucherDisplayName(selected.first)
                : 'Auto';
    final subtitle = hasSelected
        ? 'Voucher terbaik sudah dipakai otomatis'
        : totalKnownVouchers > 0
            ? '$totalKnownVouchers voucher bisa dicek'
            : 'Voucher terbaik akan dipakai otomatis';
    final chipColor =
        hasSelected ? const Color(0xFFE91E63) : const Color(0xFF667085);
    final chipBg =
        hasSelected ? const Color(0xFFFFE8EF) : const Color(0xFFF2F4F7);

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voucher Natalo',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasSelected
                            ? const Color(0xFFE91E63)
                            : const Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: widget.onViewVouchers,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.loading) ...[
                        SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: chipColor,
                          ),
                        ),
                        const SizedBox(width: 7),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 118),
                        child: Text(
                          hasSelected ? chipText : 'Lihat voucher',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: chipColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: chipColor,
                        size: 18,
                      ),
                    ],
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

bool _voucherTextLooksLikeCode(String value) {
  final text = value.trim();
  if (text.length < 4 || text.length > 28) return false;
  if (text.contains(RegExp(r'\s'))) return false;
  final upper = text.toUpperCase();
  if (text != upper) return false;
  return RegExp(r'^[A-Z0-9_-]+$').hasMatch(text) &&
      RegExp(r'[0-9_-]').hasMatch(text);
}

String _voucherDisplayName(MemberVoucher voucher) {
  final title = voucher.title.trim();
  if (title.isNotEmpty &&
      !_voucherTextLooksLikeUrl(title) &&
      !_voucherTextLooksLikeCode(title)) {
    return title;
  }

  final code = voucher.code.trim();
  if (code.isNotEmpty &&
      !_voucherTextLooksLikeUrl(code) &&
      !_voucherTextLooksLikeCode(code)) {
    return voucher.isPrivateManual ? 'Kode $code' : code;
  }

  if (voucher.discount > 0) {
    final amount = formatRupiah(voucher.discount.toDouble());
    if (voucher.isFreeShipping || voucher.isShippingDiscount) {
      return 'Diskon Ongkir $amount';
    }
    if (voucher.isLoyaltyClaim) return 'Voucher Poin $amount';
    if (voucher.isPrivateManual) return 'Voucher Khusus $amount';
    return 'Diskon Produk $amount';
  }

  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Voucher Gratis Ongkir';
  }
  if (voucher.isLoyaltyClaim) return 'Voucher Reward Poin';
  if (voucher.isPrivateManual) return 'Kode Voucher Khusus';
  return 'Voucher Diskon Produk';
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

Color _voucherAccentColor(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return const Color(0xFF12A66A);
  }
  if (voucher.isLoyaltyClaim) return const Color(0xFF7C3AED);
  return const Color(0xFFE91E63);
}

IconData _voucherIcon(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return Icons.local_shipping_outlined;
  }
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

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.46,
        maxChildSize: 0.92,
        builder: (context, controller) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  height: 5,
                  width: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Voucher Natalo',
                              style: TextStyle(
                                color: Color(0xFF17202A),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Cek voucher yang dipakai otomatis dan voucher lain.',
                              style: TextStyle(
                                color: Color(0xFF667085),
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
                const Divider(height: 1, color: Color(0xFFE8EEF7)),
                Expanded(
                  child: hasAny
                      ? ListView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
      ),
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
      style: const TextStyle(
        color: Color(0xFF667085),
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

  @override
  Widget build(BuildContext context) {
    final totalSavings = vouchers.fold<int>(
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
                      '${vouchers.length} voucher terpakai',
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
          ...vouchers.map(
            (voucher) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AppliedVoucherLine(
                voucher: voucher,
                onRemove: () => onRemove(voucher),
              ),
            ),
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
          Text(
            _voucherSavingsText(voucher),
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
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
    final accent = _voucherAccentColor(voucher);
    final foreground =
        enabled ? const Color(0xFF17202A) : const Color(0xFF98A2B3);
    final title = _voucherDisplayName(voucher);
    final subtitle = voucher.disabledReason?.isNotEmpty == true
        ? voucher.disabledReason!
        : _voucherDescriptionText(voucher);

    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFE8EEF7),
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
                          style: const TextStyle(
                            color: Color(0xFF98A2B3),
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
                      color: enabled
                          ? const Color(0xFF667085)
                          : const Color(0xFF98A2B3),
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
                        color: enabled ? accent : const Color(0xFF98A2B3),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Belum ada voucher yang bisa digunakan untuk pesanan ini.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF667085),
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
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => onApply(),
      decoration: InputDecoration(
        hintText: 'Kode Manual',
        hintStyle: const TextStyle(
          color: Color(0xFF98A2B3),
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
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE8EEF7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _brandBlue, width: 1.3),
        ),
      ),
    );
  }
}
