import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import '../services/member_service.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../utils/in_app_browser.dart';
import '../services/shipping_service.dart';
import '../services/voucher_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../services/app_analytics.dart';
import '../utils/app_review.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_motion.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';
import '../widgets/order_success_overlay.dart';

const _brandBlue = NataloColors.nataloBlue;

enum _VoucherPickType { member, manualCode, clear }

class _VoucherPickResult {
  final _VoucherPickType type;
  final MemberVoucher? voucher;
  final String? code;

  const _VoucherPickResult._({
    required this.type,
    this.voucher,
    this.code,
  });

  const _VoucherPickResult.member(MemberVoucher voucher)
      : this._(type: _VoucherPickType.member, voucher: voucher);

  const _VoucherPickResult.manualCode(String code)
      : this._(type: _VoucherPickType.manualCode, code: code);

  const _VoucherPickResult.clear() : this._(type: _VoucherPickType.clear);
}

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
  // Voucher state — fetched dari /api/cart/vouchers, di-refresh setiap
  // subtotal berubah (cart updated). _selectedVoucher null = tidak pakai voucher.
  List<MemberVoucher> _availableVouchers = const [];
  List<MemberVoucher> _unavailableVouchers = const [];
  MemberVoucher? _selectedVoucher;
  MemberVoucher? _selectedManualVoucher;
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
      : cartStore.total;

  double get _itemsSubtotal =>
      _checkoutPricing?.subtotal.toDouble() ?? _localItemsSubtotal;

  double get _shippingCost =>
      _checkoutPricing?.shippingCost.toDouble() ??
      _selectedRate.price.toDouble();

  double get _voucherDiscount =>
      _checkoutPricing?.discountAmount.toDouble() ??
      ((_selectedVoucher?.discount ?? 0) +
              (_selectedManualVoucher?.discount ?? 0))
          .toDouble();

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
    setState(() {
      _shippingRates = result.rates;
      _selectedRate = result.rates.first;
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
        _selectedVoucher = null;
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
        voucherCode: _selectedVoucher?.code,
        customerVoucherCode: _selectedVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
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
        _availableVouchers = recalc.availableVouchers;
        _unavailableVouchers = recalc.unavailableVouchers;
        _selectedVoucher = recalc.appliedCustomerVoucher;
        _selectedManualVoucher = recalc.appliedManualVoucher;
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

  Future<void> _openVoucherSheet() async {
    AppHaptics.tap();
    final picked = await showModalBottomSheet<_VoucherPickResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _VoucherSheet(
        available: _availableVouchers,
        unavailable: _unavailableVouchers,
        selectedCode: _selectedVoucher?.code,
        selectedManualCode: _selectedManualVoucher?.code,
        subtotal: _itemsSubtotal.round(),
      ),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      switch (picked.type) {
        case _VoucherPickType.member:
          _selectedVoucher = picked.voucher;
          _autoVoucherSuppressed = false;
          break;
        case _VoucherPickType.manualCode:
          final code = picked.code?.trim() ?? '';
          _selectedManualVoucher = MemberVoucher(
            code: code,
            title: 'Kode promo $code',
            description: 'Menunggu validasi server.',
            expiresAt: DateTime.now().add(const Duration(days: 30)),
          );
          _autoVoucherSuppressed = false;
          break;
        case _VoucherPickType.clear:
          _selectedVoucher = null;
          _selectedManualVoucher = null;
          _autoVoucherSuppressed = true;
          break;
      }
    });
    await _syncCheckoutPricing(autoApply: !_autoVoucherSuppressed);
    if (_selectedVoucher != null || _selectedManualVoucher != null) {
      AppHaptics.success();
    }
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
        voucherCode: _selectedVoucher?.code,
        customerVoucherCode: _selectedVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
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
        voucherCode: _selectedVoucher?.code,
        manualVoucherCode: _selectedManualVoucher?.code,
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
        orderNumber: result.orderNumber,
        value: _grandTotal,
        itemCount: _checkoutItems.fold<int>(
          0,
          (sum, item) => sum + item.quantity,
        ),
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
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: const AppSuccessMark(size: 92),
          title: const Text('Pesanan Dibuat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nomor order',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      result.orderNumber,
                      style: const TextStyle(
                        color: Color(0xFF17202A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cartStore.clear();
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
              },
              child: const Text('Selesai'),
            ),
            OutlinedButton(
              onPressed: () => _openCreatedOrder(createdOrder),
              child: const Text('Lihat Detail'),
            ),
            if (hasPaymentLink)
              ElevatedButton(
                onPressed: () => _openPaymentAndDetail(
                  result.paymentUrl!,
                  createdOrder,
                ),
                child: const Text('Bayar Sekarang'),
              ),
          ],
        );
      },
    );
  }

  OrderSummary _createdOrderSummary(OrderResult result) {
    return OrderSummary(
      orderNumber: result.orderNumber,
      status: 'PENDING',
      paymentStatus: _payment == 'Midtrans' ? 'PENDING' : 'PENDING',
      paymentProvider: _paymentProvider,
      paymentUrl: result.paymentUrl,
      trackingToken: result.trackingToken,
      detailUrl: result.detailUrl,
      createdAt: DateTime.now(),
      itemCount:
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
          price: item.product.finalPrice,
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
                        onTap: _openShippingSheet,
                      ),
                      const SizedBox(height: 12),
                      _VoucherSlot(
                        selected: _selectedVoucher,
                        manualSelected: _selectedManualVoucher,
                        hasAvailable: _availableVouchers.isNotEmpty,
                        loading: _loadingVouchers,
                        onTap: _openVoucherSheet,
                      ),
                      const SizedBox(height: 12),
                      _CheckoutPaymentMethodCard(
                        payment: _payment,
                        onTap: _openPaymentSheet,
                      ),
                      const SizedBox(height: 12),
                      _PaymentSummaryCard(
                        subtotal: _itemsSubtotal,
                        shippingCost: _shippingCost,
                        voucherDiscount: _voucherDiscount,
                        grandTotal: _grandTotal,
                        syncing: _syncingPricing,
                        syncFailed: _voucherSyncFailed,
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
                title: Text(address.label),
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
  final VoidCallback onTap;

  const _CheckoutShippingMethodCard({
    required this.rates,
    required this.selected,
    required this.loading,
    required this.message,
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
              const _CheckoutSectionIcon(icon: Icons.local_shipping_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metode Pengiriman',
                      style: TextStyle(
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
                      selected.price == 0
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
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CheckoutInlineNotice(message: message!),
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
              _CheckoutSectionIcon(
                icon: rate.isSelfPickup
                    ? Icons.storefront_rounded
                    : Icons.local_shipping_rounded,
                color: disabled ? const Color(0xFF98A2B3) : _brandBlue,
                background: disabled
                    ? const Color(0xFFF2F4F7)
                    : const Color(0xFFEAF3FF),
              ),
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
                      disabled
                          ? rate.unavailableReason ?? 'Tidak tersedia'
                          : rate.duration,
                      maxLines: 1,
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
  final double shippingCost;
  final double voucherDiscount;
  final double grandTotal;
  final bool syncing;
  final bool syncFailed;

  const _PaymentSummaryCard({
    required this.subtotal,
    required this.shippingCost,
    required this.voucherDiscount,
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
          if (voucherDiscount > 0)
            _SummaryLine(
              label: 'Voucher',
              value: '-${formatRupiah(voucherDiscount)}',
              discount: true,
            ),
          _SummaryLine(
            label: 'Ongkir',
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
  final VoidCallback onPressed;
  final bool submitting;
  final bool disabled;
  final bool visible;

  const _CheckoutBottomBar({
    required this.total,
    required this.onPressed,
    required this.submitting,
    this.disabled = false,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
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
      body: 'Belum ada item untuk checkout.',
      buttonLabel: 'Pilih Produk',
      onPressed: () => Navigator.pushReplacementNamed(context, '/products'),
    );
  }
}

class _VoucherSlot extends StatelessWidget {
  final MemberVoucher? selected;
  final MemberVoucher? manualSelected;
  final bool hasAvailable;
  final bool loading;
  final VoidCallback onTap;

  const _VoucherSlot({
    required this.selected,
    required this.manualSelected,
    required this.hasAvailable,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelected = selected != null || manualSelected != null;
    final selectedCount =
        (selected == null ? 0 : 1) + (manualSelected == null ? 0 : 1);
    final selectedDiscount =
        ((selected?.discount ?? 0) + (manualSelected?.discount ?? 0))
            .toDouble();
    final chipText = selectedDiscount > 0
        ? 'Hemat ${formatRupiah(selectedDiscount)}'
        : selectedCount > 1
            ? '$selectedCount voucher'
            : selected?.code ?? manualSelected?.code ?? 'Aktif';
    final subtitle = hasSelected
        ? chipText
        : hasAvailable
            ? 'Lihat voucher'
            : 'Belum ada voucher tersedia';
    final chipColor = hasSelected
        ? const Color(0xFFE91E63)
        : hasAvailable
            ? _brandBlue
            : const Color(0xFF667085);
    final chipBg = hasSelected
        ? const Color(0xFFFFE8EF)
        : hasAvailable
            ? const Color(0xFFEAF3FF)
            : const Color(0xFFF2F4F7);

    return _CheckoutCardShell(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _CheckoutSectionIcon(
            icon: Icons.confirmation_number_rounded,
            color: hasSelected ? const Color(0xFFE91E63) : _brandBlue,
            background:
                hasSelected ? const Color(0xFFFFE8EF) : const Color(0xFFEAF3FF),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voucher & Promo',
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
          if (loading)
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasSelected ? chipText : (hasAvailable ? 'Lihat' : 'Info'),
                    style: TextStyle(
                      color: chipColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: chipColor,
                    size: 17,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet voucher picker. Match struktur PWA CheckoutVoucherCard
/// modal: section "Tersedia" (applicable) + section "Belum Tersedia"
/// (visible tapi disabled). Tap voucher applicable → return ke checkout.
class _VoucherSheet extends StatefulWidget {
  final List<MemberVoucher> available;
  final List<MemberVoucher> unavailable;
  final String? selectedCode;
  final String? selectedManualCode;
  final int subtotal;

  const _VoucherSheet({
    required this.available,
    required this.unavailable,
    required this.selectedCode,
    required this.selectedManualCode,
    required this.subtotal,
  });

  @override
  State<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends State<_VoucherSheet> {
  final _codeCtrl = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateManualCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _validationError = null);
    Navigator.pop(context, _VoucherPickResult.manualCode(code));
  }

  List<MemberVoucher> get available => widget.available;
  List<MemberVoucher> get unavailable => widget.unavailable;
  String? get selectedCode => widget.selectedCode;
  String? get selectedManualCode => widget.selectedManualCode;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      child: GlassSurface(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    height: 5,
                    width: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Voucher Member',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  available.isEmpty
                      ? 'Belum ada voucher yang bisa dipakai untuk pesanan ini.'
                      : '${available.length} voucher tersedia untuk pesanan ini',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                // Manual voucher input — user paste kode dari email/share
                // yang tidak otomatis muncul di list (mis. SELLER_MANUAL).
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'Punya kode voucher? Ketik di sini',
                          isDense: true,
                          errorText: _validationError,
                          prefixIcon: const Icon(
                            Icons.local_offer_outlined,
                            size: 18,
                          ),
                        ),
                        onSubmitted: (_) => _validateManualCode(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _validateManualCode,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text('Pakai'),
                      ),
                    ),
                  ],
                ),
                if (selectedManualCode != null &&
                    selectedManualCode!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        'Kode aktif: $selectedManualCode',
                        style: const TextStyle(
                          color: _brandBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      if (available.isNotEmpty) ...[
                        const _VoucherSectionHeader(label: 'Tersedia'),
                        const SizedBox(height: 8),
                        for (final v in available)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _VoucherRow(
                              voucher: v,
                              selected: v.code == selectedCode,
                              enabled: true,
                              onTap: () => Navigator.pop(
                                context,
                                _VoucherPickResult.member(v),
                              ),
                            ),
                          ),
                        if (selectedCode != null || selectedManualCode != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: TextButton.icon(
                              onPressed: () => Navigator.pop(
                                context,
                                const _VoucherPickResult.clear(),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Lepas voucher'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                      ],
                      if (unavailable.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const _VoucherSectionHeader(label: 'Belum Tersedia'),
                        const SizedBox(height: 8),
                        for (final v in unavailable)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _VoucherRow(
                              voucher: v,
                              selected: false,
                              enabled: false,
                              onTap: null,
                            ),
                          ),
                      ],
                      if (available.isEmpty && unavailable.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'Belum ada voucher untuk akun ini.',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoucherSectionHeader extends StatelessWidget {
  final String label;
  const _VoucherSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _VoucherRow extends StatelessWidget {
  final MemberVoucher voucher;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _VoucherRow({
    required this.voucher,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor =
        enabled ? const Color(0xFF17202A) : const Color(0xFF9CA3AF);
    final subtitleColor =
        enabled ? const Color(0xFF6B7280) : const Color(0xFFE5E7EB);
    final borderColor = selected
        ? const Color(0xFFF59E0B)
        : (enabled ? const Color(0xFFE5E7EB) : const Color(0xFFEFF2F6));
    final bgColor = selected
        ? const Color(0xFFFFFBEB)
        : (enabled ? Colors.white : const Color(0xFFF8FAFC));

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: AppPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                      : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.local_offer_rounded,
                  color: enabled
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF9CA3AF),
                ),
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
                            voucher.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (enabled && voucher.discount > 0)
                          Text(
                            '-${formatRupiah(voucher.discount.toDouble())}',
                            style: const TextStyle(
                              color: NataloColors.discountRed,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      voucher.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (!enabled && voucher.disabledReason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        voucher.disabledReason!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Kode: ${voucher.code}',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
