import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/product.dart';
import '../services/member_service.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/animated_counter.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_product_image.dart';
import '../widgets/glass_surface.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_product_card.dart';

const _brandBlue = NataloColors.nataloBlue;
const _discountRed = Color(0xFFE53958);
const _discountRedSoft = Color(0xFFFFF1F4);
const _discountRedBorder = Color(0xFFFFB8C8);
const _shippingGreen = Color(0xFF12A66A);
const _shippingGreenSoft = Color(0xFFECFDF3);
const _shippingGreenBorder = Color(0xFFA6F4C5);
const _checkoutBarHeight = 74.0;
const _voucherBarHeight = 64.0;
const _cartBossOpenCountKey = 'natalo_cart_boss_open_count_v1';
const _cartBossRefreshEvery = 3;
const _shippingVoucherCode = '__shipping_free__';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Product> _recentlyViewed = const [];
  List<Product> _bossProducts = const [];
  bool _loadingRecentlyViewed = false;
  bool _loadingBossProducts = false;
  bool _loadingMoreBossProducts = false;
  bool _bossProductsHasMore = true;
  String? _bossProductsCursor;
  Timer? _voucherBarTimer;
  bool _voucherBarVisible = true;
  List<MemberVoucher> _availableDiscountVouchers = const [];
  List<MemberVoucher> _unavailableDiscountVouchers = const [];
  MemberVoucher? _appliedDiscountVoucher;
  bool _appliedShippingVoucher = false;
  bool _isManualVoucherSelected = false;
  String? _manualVoucherCode;
  int _lastVoucherSubtotal = -1;
  bool _loadingVouchers = false;
  // Multi-select state lokal — track key item yang user pilih untuk checkout.
  // Default semua item ter-select saat first load (backward compatible). User
  // bisa toggle individual atau select all/none. Tidak persist disk — reset
  // saat keluar screen.
  Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRecentlyViewed();
    _loadBossProducts();
    _scrollController.addListener(_onCartScroll);
    // Default select semua cart items yang ada saat first build.
    _selectedIds = cartStore.items.map((i) => i.key).toSet();
    cartStore.addListener(_onCartChanged);
    memberStore.addListener(_onMemberChanged);
    recentlyViewedStore.addListener(_loadRecentlyViewed);
    _syncVouchersForSelection();
  }

  Future<void> _loadRecentlyViewed() async {
    if (mounted) {
      setState(() => _loadingRecentlyViewed = true);
    } else {
      _loadingRecentlyViewed = true;
    }
    final cartProductIds =
        cartStore.items.map((item) => item.product.id).toSet();
    final localViewed = recentlyViewedStore.items
        .where((product) => !cartProductIds.contains(product.id))
        .toList();
    final localViewedIds = localViewed.map((product) => product.id).toList();
    List<Product> result = const [];
    try {
      result = await productService.fetchRecentlyViewed(
        ids: localViewedIds,
        excludeIds: cartProductIds.toList(),
        limit: 8,
      );
    } catch (_) {
      result = const [];
    }
    if (!mounted) return;
    setState(() {
      _recentlyViewed =
          result.isNotEmpty ? result : localViewed.take(8).toList();
      _loadingRecentlyViewed = false;
    });
  }

  @override
  void dispose() {
    _voucherBarTimer?.cancel();
    _scrollController.removeListener(_onCartScroll);
    _scrollController.dispose();
    cartStore.removeListener(_onCartChanged);
    memberStore.removeListener(_onMemberChanged);
    recentlyViewedStore.removeListener(_loadRecentlyViewed);
    super.dispose();
  }

  Future<void> _loadBossProducts() async {
    setState(() => _loadingBossProducts = true);
    var openCount = 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      openCount = (prefs.getInt(_cartBossOpenCountKey) ?? 0) + 1;
      await prefs.setInt(_cartBossOpenCountKey, openCount);
    } catch (_) {
      openCount = 1;
    }

    final rotation = (openCount - 1) ~/ _cartBossRefreshEvery;
    final startOffset = rotation * 8;
    final startCursor = startOffset > 0 ? '$startOffset' : null;
    var page = await productService.fetchProductsPage(
      cursor: startCursor,
      limit: 8,
      inStock: true,
      hasPrice: true,
      withImage: true,
    );
    if (page.products.isEmpty && startCursor != null) {
      page = await productService.fetchProductsPage(
        limit: 8,
        inStock: true,
        hasPrice: true,
        withImage: true,
      );
    }
    if (!mounted) return;
    setState(() {
      _bossProducts = page.products;
      _bossProductsCursor = page.nextCursor;
      _bossProductsHasMore = page.hasMore;
      _loadingBossProducts = false;
    });
  }

  void _onCartScroll() {
    if (!_scrollController.hasClients ||
        _loadingBossProducts ||
        _loadingMoreBossProducts ||
        !_bossProductsHasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 520) {
      _loadMoreBossProducts();
    }
  }

  Future<void> _loadMoreBossProducts() async {
    if (_loadingMoreBossProducts || !_bossProductsHasMore) return;
    setState(() => _loadingMoreBossProducts = true);
    final page = await productService.fetchProductsPage(
      cursor: _bossProductsCursor,
      limit: 8,
      inStock: true,
      hasPrice: true,
      withImage: true,
    );
    if (!mounted) return;
    final existingIds = _bossProducts.map((product) => product.id).toSet();
    final nextProducts = page.products
        .where((product) => !existingIds.contains(product.id))
        .toList();
    setState(() {
      _bossProducts = [..._bossProducts, ...nextProducts];
      _bossProductsCursor = page.nextCursor;
      _bossProductsHasMore = page.hasMore;
      _loadingMoreBossProducts = false;
    });
  }

  void _onCartChanged() {
    // Auto-add baru added cart items ke selection (default semua selected).
    // Prune selected IDs yang sudah tidak di cart (saat item di-remove).
    final cartKeys = cartStore.items.map((i) => i.key).toSet();
    setState(() {
      // Add semua key yang belum di set (new items).
      for (final key in cartKeys) {
        _selectedIds.add(key);
      }
      // Prune key yang sudah tidak di cart.
      _selectedIds.retainAll(cartKeys);
    });
    _syncVouchersForSelection();
  }

  void _onMemberChanged() {
    _syncVouchersForSelection();
  }

  // ── Helper getters untuk multi-select & price summary ──

  List<CartItem> get _selectedItems =>
      cartStore.items.where((item) => _selectedIds.contains(item.key)).toList();

  bool get _isAllSelected =>
      cartStore.items.isNotEmpty &&
      cartStore.items.every((item) => _selectedIds.contains(item.key));

  int get _selectedQuantity =>
      _selectedItems.fold<int>(0, (sum, item) => sum + item.quantity);

  double get _selectedSubtotal =>
      _selectedItems.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get _shippingEstimate => _selectedItems.isEmpty ? 0 : 15000;

  double get _voucherDiscount {
    if (_selectedItems.isEmpty) return 0;
    return _appliedDiscountVoucher?.discount.toDouble() ?? 0;
  }

  double get _shippingDiscount {
    if (_selectedItems.isEmpty || !_appliedShippingVoucher) return 0;
    return _shippingEstimate;
  }

  double get _totalVoucherSaving => _voucherDiscount + _shippingDiscount;

  bool get _shippingVoucherEligible =>
      _selectedItems.isNotEmpty && _selectedSubtotal >= 250000;

  double get _grandTotal {
    final total = _selectedSubtotal +
        _shippingEstimate -
        _voucherDiscount -
        _shippingDiscount;
    return total < 0 ? 0 : total;
  }

  Future<void> _syncVouchersForSelection() async {
    final subtotal = _selectedSubtotal.round();
    if (!memberStore.isLoggedIn || subtotal <= 0 || _selectedItems.isEmpty) {
      if (!mounted) return;
      setState(() {
        _availableDiscountVouchers = const [];
        _unavailableDiscountVouchers = const [];
        _appliedDiscountVoucher = null;
        _appliedShippingVoucher = false;
        _isManualVoucherSelected = false;
        _manualVoucherCode = null;
        _lastVoucherSubtotal = 0;
        _loadingVouchers = false;
      });
      return;
    }

    var available = _availableDiscountVouchers;
    var unavailable = _unavailableDiscountVouchers;
    if (subtotal != _lastVoucherSubtotal) {
      setState(() => _loadingVouchers = true);
      try {
        final result = await memberService.fetchCartVouchers(subtotal);
        available = result.available;
        unavailable = result.unavailable;
      } catch (_) {
        available = const [];
        unavailable = const [];
      }
      if (!mounted) return;
      setState(() {
        _availableDiscountVouchers = available;
        _unavailableDiscountVouchers = unavailable;
        _lastVoucherSubtotal = subtotal;
        _loadingVouchers = false;
      });
    }

    final bestDiscount = _bestDiscountVoucher(available);
    var nextDiscount = _appliedDiscountVoucher;
    var nextShipping = _appliedShippingVoucher && _shippingVoucherEligible;
    var manualStillEligible = false;

    if (_isManualVoucherSelected && _manualVoucherCode != null) {
      if (_manualVoucherCode == _shippingVoucherCode &&
          _shippingVoucherEligible) {
        manualStillEligible = true;
        nextShipping = true;
        nextDiscount = bestDiscount;
      } else {
        final manualDiscount =
            _findVoucherByCode(available, _manualVoucherCode!);
        if (manualDiscount != null) {
          manualStillEligible = true;
          nextDiscount = manualDiscount;
          nextShipping = _shippingVoucherEligible;
        }
      }
    }

    if (!_isManualVoucherSelected || !manualStillEligible) {
      nextDiscount = bestDiscount;
      nextShipping = _shippingVoucherEligible;
    }

    if (!mounted) return;
    setState(() {
      _appliedDiscountVoucher = nextDiscount;
      _appliedShippingVoucher = nextShipping;
      if (_isManualVoucherSelected && !manualStillEligible) {
        _isManualVoucherSelected = false;
        _manualVoucherCode = null;
      }
    });
  }

  MemberVoucher? _bestDiscountVoucher(List<MemberVoucher> vouchers) {
    final eligible = vouchers.where((voucher) => voucher.discount > 0).toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) => b.discount.compareTo(a.discount));
    return eligible.first;
  }

  MemberVoucher? _findVoucherByCode(List<MemberVoucher> vouchers, String code) {
    for (final voucher in vouchers) {
      if (voucher.code == code) return voucher;
    }
    return null;
  }

  void _hideVoucherBar() {
    _voucherBarTimer?.cancel();
    if (!_voucherBarVisible) return;
    setState(() => _voucherBarVisible = false);
  }

  void _scheduleShowVoucherBar() {
    _voucherBarTimer?.cancel();
    _voucherBarTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _voucherBarVisible) return;
      setState(() => _voucherBarVisible = true);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is UserScrollNotification) {
      _hideVoucherBar();
    }
    if (notification is ScrollEndNotification) {
      _scheduleShowVoucherBar();
    }
    return false;
  }

  void _toggleAll() {
    AppHaptics.tap();
    setState(() {
      if (_isAllSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds = cartStore.items.map((i) => i.key).toSet();
      }
    });
    _syncVouchersForSelection();
  }

  void _toggleItem(String key) {
    AppHaptics.tap();
    setState(() {
      if (_selectedIds.contains(key)) {
        _selectedIds.remove(key);
      } else {
        _selectedIds.add(key);
      }
    });
    _syncVouchersForSelection();
  }

  Future<void> _confirmRemoveSelected() async {
    if (_selectedItems.isEmpty) return;
    AppHaptics.tap();
    final count = _selectedItems.length;
    final quantity = _selectedQuantity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _CartDeleteConfirmDialog(
          count: count,
          quantity: quantity,
        );
      },
    );
    if (confirmed == true) {
      _removeSelected();
    }
  }

  void _removeSelected() {
    if (_selectedItems.isEmpty) return;
    AppHaptics.warning();
    final removedEntries = _selectedItems.map((item) {
      final index = cartStore.items.indexWhere((cart) => cart.key == item.key);
      return MapEntry(index < 0 ? 0 : index, item);
    }).toList();
    for (final item in removedEntries.map((entry) => entry.value)) {
      cartStore.remove(item.key);
    }
    _showCartDeleteSnackBar(
      context,
      message: '${removedEntries.length} produk dihapus',
      onUndo: () {
        for (final entry in removedEntries.reversed) {
          cartStore.restore(entry.value, index: entry.key);
        }
      },
    );
  }

  void _goToCheckout() {
    if (_selectedItems.isEmpty) return;
    AppHaptics.impact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (!memberStore.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masuk member dulu untuk lanjut checkout.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pushNamed(
        context,
        '/member/login',
        arguments: {'redirect': '/checkout'},
      );
      return;
    }
    Navigator.pushNamed(context, '/checkout');
  }

  Future<void> _openVoucherSheet() async {
    if (_selectedItems.isEmpty || !memberStore.isLoggedIn) return;
    final picked = await showModalBottomSheet<_CartVoucherChoice?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CartVoucherSheet(
        availableDiscounts: _availableDiscountVouchers,
        unavailableDiscounts: _unavailableDiscountVouchers,
        shippingEligible: _shippingVoucherEligible,
        shippingDiscount: _shippingEstimate.round(),
        selectedDiscountCode: _appliedDiscountVoucher?.code,
        shippingSelected: _appliedShippingVoucher,
        isManual: _isManualVoucherSelected,
        loading: _loadingVouchers,
      ),
    );
    if (picked == null) return;

    AppHaptics.success();
    setState(() {
      if (picked.remove) {
        _appliedDiscountVoucher = null;
        _appliedShippingVoucher = false;
        _isManualVoucherSelected = false;
        _manualVoucherCode = null;
        return;
      }

      _isManualVoucherSelected = true;
      _manualVoucherCode = picked.code;
      if (picked.type == _CartVoucherType.discount) {
        _appliedDiscountVoucher = picked.discountVoucher;
        _appliedShippingVoucher = _shippingVoucherEligible;
      } else {
        _appliedShippingVoucher = _shippingVoucherEligible;
        _appliedDiscountVoucher =
            _bestDiscountVoucher(_availableDiscountVouchers);
      }
    });
  }

  // _syncCart dihapus — cloud sync icon di-remove dari AppBar (per
  // simplified design). Cart auto-sync sudah via login flow.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Custom title dengan count subtitle — match PWA cart header
      // "Keranjang\n0 jenis produk (0 item)".
      // AppBar simplified per reference pattern — title "Keranjang" pakai
      // theme default (18/w700). Subtitle count diturunkan jadi inline
      // bawah list, bukan di header. Action cuma "Kosongkan" saat ada item.
      appBar: AppBar(
        title: const Text('Keranjang'),
        actions: [
          AnimatedBuilder(
            animation: cartStore,
            builder: (context, _) {
              // Conditional action: delete saat ada selected, storefront
              // saat cart kosong / tidak ada selection.
              if (cartStore.items.isEmpty) {
                return const SizedBox.shrink();
              }
              if (_selectedItems.isNotEmpty) {
                return IconButton(
                  tooltip: 'Hapus terpilih',
                  onPressed: _confirmRemoveSelected,
                  icon: const Icon(Icons.delete_outline_rounded),
                );
              }
              return TextButton(
                onPressed: cartStore.clear,
                child: const Text('Kosongkan'),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: cartStore,
        builder: (context, _) {
          final items = cartStore.items;
          if (items.isEmpty) {
            return _EmptyCartState(
              controller: _scrollController,
              recentlyViewed: _recentlyViewed,
              bossProducts: _bossProducts,
              loadingBossProducts: _loadingBossProducts,
              loadingMoreBossProducts: _loadingMoreBossProducts,
            );
          }

          final bottomSafe = MediaQuery.paddingOf(context).bottom;
          final showVoucherArea = memberStore.isLoggedIn;
          final stickyBottomPadding = _checkoutBarHeight +
              (showVoucherArea ? _voucherBarHeight : 0) +
              bottomSafe +
              36;

          return Stack(
            children: [
              Listener(
                onPointerDown: (_) => _hideVoucherBar(),
                onPointerMove: (_) => _hideVoucherBar(),
                onPointerUp: (_) => _scheduleShowVoucherBar(),
                onPointerCancel: (_) => _scheduleShowVoucherBar(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      stickyBottomPadding,
                    ),
                    children: [
                      // ── Select all card ──
                      _SelectAllCard(
                        selected: _isAllSelected,
                        totalProduct: items.length,
                        selectedProduct: _selectedItems.length,
                        onTap: _toggleAll,
                      ),
                      const SizedBox(height: 12),
                      // ── Cart items dengan checkbox per item ──
                      for (var i = 0; i < items.length; i++) ...[
                        _CartItemCard(
                          item: items[i],
                          index: i,
                          selected: _selectedIds.contains(items[i].key),
                          onToggleSelected: () => _toggleItem(items[i].key),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _CartRecommendationsSection(
                        title: 'Yuk dilihat lagi',
                        products: _recentlyViewed,
                        loading: _loadingRecentlyViewed,
                        showLoadingPlaceholder: false,
                      ),
                      const SizedBox(height: 18),
                      _CartRecommendationsSection(
                        title: 'Ayoo diborong bossku',
                        products: _bossProducts,
                        loading: _loadingBossProducts,
                        loadingMore: _loadingMoreBossProducts,
                        showLoadingPlaceholder: false,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Material(
                  color: NataloColors.surface,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showVoucherArea)
                        ClipRect(
                          child: AnimatedContainer(
                            height: _voucherBarVisible ? _voucherBarHeight : 0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: AnimatedSlide(
                              offset: _voucherBarVisible
                                  ? Offset.zero
                                  : const Offset(0, 1),
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: AnimatedOpacity(
                                opacity: _voucherBarVisible ? 1 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: IgnorePointer(
                                  ignoring: !_voucherBarVisible,
                                  child: _StickyVoucherBar(
                                    hasSelection: _selectedItems.isNotEmpty,
                                    loading: _loadingVouchers,
                                    discountVoucher: _appliedDiscountVoucher,
                                    discountAmount: _voucherDiscount,
                                    shippingSelected: _appliedShippingVoucher,
                                    shippingDiscount: _shippingDiscount,
                                    totalSaving: _totalVoucherSaving,
                                    onTap: _selectedItems.isEmpty
                                        ? null
                                        : () {
                                            AppHaptics.tap();
                                            _openVoucherSheet();
                                          },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      _CartSummaryBar(
                        grandTotal: _grandTotal,
                        selectedQuantity: _selectedQuantity,
                        disabled: _selectedItems.isEmpty,
                        onCheckout: _goToCheckout,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CartDeleteConfirmDialog extends StatelessWidget {
  final int count;
  final int quantity;

  const _CartDeleteConfirmDialog({
    required this.count,
    required this.quantity,
  });

  @override
  Widget build(BuildContext context) {
    final body = quantity == count
        ? 'Produk terpilih akan dihapus dari keranjang.'
        : '$quantity item dari produk terpilih akan dihapus dari keranjang.';

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDF2),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFC8D5)),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFE11D48),
                size: 25,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'Yakin mau hapus $count produk?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brandBlue,
                        side: const BorderSide(color: _brandBlue, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: const Text('Hapus'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cart item card baru — match reference pattern:
/// - Checkbox di kiri (multi-select)
/// - Image 82×92 dengan discount badge
/// - Title + brand•category + stock
/// - Swipe kiri untuk hapus + undo snackbar
/// - Bottom row: price + strikethrough + discount% + qty stepper
class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final int index;
  final bool selected;
  final VoidCallback onToggleSelected;

  const _CartItemCard({
    required this.item,
    required this.index,
    required this.selected,
    required this.onToggleSelected,
  });

  void _removeWithUndo(BuildContext context) {
    cartStore.remove(item.key);
    _showCartDeleteSnackBar(
      context,
      message: 'Produk telah dihapus',
      onUndo: () => cartStore.restore(item, index: index),
    );
  }

  void _openProductDetail(BuildContext context) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/product-detail', arguments: item.product);
  }

  @override
  Widget build(BuildContext context) {
    final price = item.effectivePrice;
    final regular = item.product.price;
    final hasDiscount = regular > price;
    final discountPercent =
        hasDiscount ? (((regular - price) / regular) * 100).round() : 0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: Duration(milliseconds: 220 + (index * 35).clamp(0, 180)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 24),
            child: Transform.scale(scale: value, child: child),
          ),
        );
      },
      child: Dismissible(
        key: ValueKey('cart-item-${item.key}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => _removeWithUndo(context),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: selected,
                      activeColor: _brandBlue,
                      onChanged: (_) => onToggleSelected(),
                    ),
                    InkWell(
                      onTap: () => _openProductDetail(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Container(
                            width: 82,
                            height: 92,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5FF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: AppProductImage(
                              imageUrl: item.product.imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (discountPercent > 0)
                            Positioned(
                              left: 7,
                              top: 7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '-$discountPercent%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _openProductDetail(context),
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 92,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF17202A),
                                  fontSize: 14,
                                  height: 1.2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${item.product.brand} • ${item.product.category}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.variantLabel != null) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF5FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.variantLabel!,
                                    style: const TextStyle(
                                      color: _brandBlue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                'Stok ${item.effectiveStock}',
                                style: TextStyle(
                                  color: item.effectiveStock <= 10
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF16A34A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatRupiah(price),
                              style: NataloTextStyles.cartPrice.copyWith(
                                fontSize: 15,
                              ),
                            ),
                            if (hasDiscount) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    formatRupiah(regular),
                                    style: const TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '-$discountPercent%',
                                    style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      _QtyStepper(
                        quantity: item.quantity,
                        maxQty: item.effectiveStock,
                        onSetQuantity: (quantity) {
                          AppHaptics.tap();
                          cartStore.updateQuantity(item.key, quantity);
                        },
                        onDecrement: () {
                          AppHaptics.tap();
                          if (item.quantity <= 1) {
                            _removeWithUndo(context);
                          } else {
                            cartStore.updateQuantity(
                              item.key,
                              item.quantity - 1,
                            );
                          }
                        },
                        onIncrement: () {
                          AppHaptics.tap();
                          cartStore.updateQuantity(
                            item.key,
                            item.quantity + 1,
                          );
                        },
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

/// Qty stepper match PWA app/cart/page.tsx — single rounded-full border
/// wrapper dengan 3 cell: − / qty / +. Disabled state untuk + saat
/// quantity >= stock.
class _QtyStepper extends StatefulWidget {
  final int quantity;
  final int maxQty;
  final ValueChanged<int> onSetQuantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QtyStepper({
    required this.quantity,
    required this.maxQty,
    required this.onSetQuantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  State<_QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<_QtyStepper> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _commitDebounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.quantity}');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _QtyStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != '${widget.quantity}') {
      _controller.text = '${widget.quantity}';
    }
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commitDebounce?.cancel();
      _commitInlineQuantity(resetEmpty: true);
    }
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _scheduleInlineCommit(String value) {
    _commitDebounce?.cancel();
    if (value.trim().isEmpty) return;
    _commitDebounce = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      _commitInlineQuantity(resetEmpty: false);
    });
  }

  void _commitInlineQuantity({required bool resetEmpty}) {
    final raw = _controller.text.trim();
    if (raw.isEmpty && !resetEmpty) return;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0 || widget.maxQty <= 0) {
      _controller.text = '${widget.quantity}';
      _selectAll();
      return;
    }

    final limit = widget.maxQty < 1 ? 1 : widget.maxQty;
    final next = parsed.clamp(1, limit).toInt();
    _controller.text = '$next';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );

    if (next != widget.quantity) {
      widget.onSetQuantity(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canIncrement = widget.quantity < widget.maxQty;
    final decrementIsDelete = widget.quantity <= 1;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperCell(
            onTap: widget.onDecrement,
            child: decrementIsDelete
                ? const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Color(0xFF6B7280),
                  )
                : const Text(
                    '−',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
          ),
          SizedBox(
            width: 46,
            height: 36,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.maxQty > 0,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onTap: _selectAll,
              onChanged: _scheduleInlineCommit,
              onEditingComplete: () {
                _commitDebounce?.cancel();
                _commitInlineQuantity(resetEmpty: true);
                _focusNode.unfocus();
              },
              onTapOutside: (_) {
                _commitDebounce?.cancel();
                _commitInlineQuantity(resetEmpty: true);
                _focusNode.unfocus();
              },
              onSubmitted: (_) {
                _commitDebounce?.cancel();
                _commitInlineQuantity(resetEmpty: true);
                _focusNode.unfocus();
              },
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          _StepperCell(
            enabled: canIncrement,
            onTap: canIncrement ? widget.onIncrement : null,
            child: Text(
              '+',
              style: TextStyle(
                color: canIncrement
                    ? const Color(0xFF6B7280)
                    : const Color(0xFFE5E7EB),
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperCell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  const _StepperCell({
    required this.child,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 36,
        width: 36,
        child: Center(child: child),
      ),
    );
  }
}

void _showCartDeleteSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  AppToast.showCartDeleted(
    context,
    message,
    duration: const Duration(milliseconds: 1400),
    onUndo: onUndo,
  );
}

enum _CartVoucherType { discount, shipping }

class _CartVoucherChoice {
  final _CartVoucherType? type;
  final String? code;
  final MemberVoucher? discountVoucher;
  final bool remove;

  const _CartVoucherChoice._({
    this.type,
    this.code,
    this.discountVoucher,
    this.remove = false,
  });

  factory _CartVoucherChoice.discount(MemberVoucher voucher) {
    return _CartVoucherChoice._(
      type: _CartVoucherType.discount,
      code: voucher.code,
      discountVoucher: voucher,
    );
  }

  factory _CartVoucherChoice.shipping() {
    return const _CartVoucherChoice._(
      type: _CartVoucherType.shipping,
      code: _shippingVoucherCode,
    );
  }

  factory _CartVoucherChoice.removeAll() {
    return const _CartVoucherChoice._(remove: true);
  }
}

class _StickyVoucherBar extends StatelessWidget {
  final bool hasSelection;
  final bool loading;
  final MemberVoucher? discountVoucher;
  final double discountAmount;
  final bool shippingSelected;
  final double shippingDiscount;
  final double totalSaving;
  final VoidCallback? onTap;

  const _StickyVoucherBar({
    required this.hasSelection,
    required this.loading,
    required this.discountVoucher,
    required this.discountAmount,
    required this.shippingSelected,
    required this.shippingDiscount,
    required this.totalSaving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = discountVoucher != null && discountAmount > 0;
    final hasShipping = shippingSelected && shippingDiscount > 0;
    final hasSaving = hasSelection && totalSaving > 0;
    final chipText = hasDiscount
        ? 'Diskon ${formatRupiah(discountAmount)}'
        : hasShipping
            ? 'Gratis Ongkir'
            : loading
                ? 'Cek...'
                : 'Pilih';
    final chipColor = hasDiscount
        ? _discountRed
        : hasShipping
            ? _shippingGreen
            : _brandBlue;
    final chipBackground = hasDiscount
        ? _discountRedSoft
        : hasShipping
            ? _shippingGreenSoft
            : const Color(0xFFEAF5FF);
    final chipBorder = hasDiscount
        ? _discountRedBorder
        : hasShipping
            ? _shippingGreenBorder
            : const Color(0xFFBFDBFE);
    final chipIcon = hasShipping && !hasDiscount
        ? Icons.local_shipping_outlined
        : Icons.local_offer_rounded;
    final subtitle = !hasSelection
        ? 'Pilih produk untuk cek promo'
        : loading
            ? 'Mencari promo yang cocok'
            : hasSaving
                ? 'Hemat ${formatRupiah(totalSaving)}'
                : 'Tap untuk cek voucher';

    return Material(
      color: NataloColors.surface,
      child: Container(
        height: _voucherBarHeight,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5EAF1))),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: chipBackground,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: chipBorder),
                  ),
                  child: Icon(
                    Icons.confirmation_number_outlined,
                    color: chipColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Voucher untukmu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _VoucherMiniChip(
                  text: chipText,
                  color: chipColor,
                  background: chipBackground,
                  border: chipBorder,
                  icon: chipIcon,
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  color: hasSelection
                      ? const Color(0xFF64748B)
                      : const Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoucherMiniChip extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final Color border;
  final IconData icon;

  const _VoucherMiniChip({
    required this.text,
    required this.color,
    required this.background,
    required this.border,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartVoucherSheet extends StatefulWidget {
  final List<MemberVoucher> availableDiscounts;
  final List<MemberVoucher> unavailableDiscounts;
  final bool shippingEligible;
  final int shippingDiscount;
  final String? selectedDiscountCode;
  final bool shippingSelected;
  final bool isManual;
  final bool loading;

  const _CartVoucherSheet({
    required this.availableDiscounts,
    required this.unavailableDiscounts,
    required this.shippingEligible,
    required this.shippingDiscount,
    required this.selectedDiscountCode,
    required this.shippingSelected,
    required this.isManual,
    required this.loading,
  });

  @override
  State<_CartVoucherSheet> createState() => _CartVoucherSheetState();
}

class _CartVoucherSheetState extends State<_CartVoucherSheet> {
  _CartVoucherType? _selectedType;
  String? _selectedCode;
  MemberVoucher? _selectedDiscount;

  @override
  void initState() {
    super.initState();
    if (widget.selectedDiscountCode != null) {
      _selectedType = _CartVoucherType.discount;
      _selectedCode = widget.selectedDiscountCode;
      for (final voucher in widget.availableDiscounts) {
        if (voucher.code == widget.selectedDiscountCode) {
          _selectedDiscount = voucher;
          break;
        }
      }
    } else if (widget.shippingSelected) {
      _selectedType = _CartVoucherType.shipping;
      _selectedCode = _shippingVoucherCode;
    }
  }

  void _pickDiscount(MemberVoucher voucher) {
    setState(() {
      _selectedType = _CartVoucherType.discount;
      _selectedCode = voucher.code;
      _selectedDiscount = voucher;
    });
  }

  void _pickShipping() {
    setState(() {
      _selectedType = _CartVoucherType.shipping;
      _selectedCode = _shippingVoucherCode;
      _selectedDiscount = null;
    });
  }

  void _applySelection() {
    if (_selectedType == _CartVoucherType.discount &&
        _selectedDiscount != null) {
      Navigator.pop(context, _CartVoucherChoice.discount(_selectedDiscount!));
      return;
    }
    if (_selectedType == _CartVoucherType.shipping && widget.shippingEligible) {
      Navigator.pop(context, _CartVoucherChoice.shipping());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasAnyVoucher =
        widget.shippingEligible || widget.availableDiscounts.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return GlassSurface(
          radius: 28,
          tint: Colors.white,
          padding: EdgeInsets.fromLTRB(18, 14, 18, 14 + bottomInset),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pilih voucher atau promo',
                      style: TextStyle(
                        color: Color(0xFF102033),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.isManual) ...[
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Voucher untukmu sudah diterapkan',
                    style: TextStyle(
                      color: _brandBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    if (widget.loading)
                      const LinearProgressIndicator(minHeight: 3),
                    if (widget.shippingEligible) ...[
                      _CartVoucherCard(
                        title: 'Gratis Ongkir',
                        subtitle:
                            'Potongan ongkir ${formatRupiah(widget.shippingDiscount)}',
                        badge: 'Ongkir',
                        icon: Icons.local_shipping_outlined,
                        accent: _shippingGreen,
                        background: _shippingGreenSoft,
                        border: _shippingGreenBorder,
                        selected: _selectedCode == _shippingVoucherCode,
                        enabled: true,
                        onTap: _pickShipping,
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final voucher in widget.availableDiscounts) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: voucher.description,
                        badge: 'Diskon',
                        trailing: formatRupiah(voucher.discount),
                        icon: Icons.local_offer_rounded,
                        accent: _discountRed,
                        background: _discountRedSoft,
                        border: _discountRedBorder,
                        selected: _selectedCode == voucher.code,
                        enabled: true,
                        onTap: () => _pickDiscount(voucher),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (!hasAnyVoucher && !widget.loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          'Belum ada voucher yang cocok',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (widget.unavailableDiscounts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Belum bisa dipakai',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final voucher in widget.unavailableDiscounts) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              'Voucher belum memenuhi syarat.',
                          badge: 'Diskon',
                          trailing: voucher.discount > 0
                              ? formatRupiah(voucher.discount)
                              : null,
                          icon: Icons.local_offer_outlined,
                          accent: _discountRed,
                          background: const Color(0xFFF8FAFC),
                          border: const Color(0xFFE2E8F0),
                          selected: false,
                          enabled: false,
                          onTap: null,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _CartVoucherChoice.removeAll()),
                    child: const Text('Hapus Voucher'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedCode == null ? null : _applySelection,
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Pakai Voucher',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartVoucherCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final String? trailing;
  final IconData icon;
  final Color accent;
  final Color background;
  final Color border;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _CartVoucherCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accent,
    required this.background,
    required this.border,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = enabled ? accent : const Color(0xFF94A3B8);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: effectiveAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: effectiveAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Terpilih',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFF102033)
                          : const Color(0xFF94A3B8),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing!,
                style: TextStyle(
                  color: effectiveAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? accent
                  : enabled
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFFE2E8F0),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section produk bawah cart. Untuk cart aktif dipakai sebagai "Yuk dilihat
/// lagi" dari riwayat produk terakhir yang user buka.
// _SavedForLaterSection removed — multi-select checkbox sudah cover
// use case "tidak checkout sekarang" (deselect saja). Cart store methods
// `moveToSaved` / `moveToCart` / `removeSaved` masih ada untuk
// backward compatibility tapi tidak di-render lagi di cart screen.

class _CartRecommendationsSection extends StatelessWidget {
  final String title;
  final List<Product> products;
  final bool loading;
  final bool loadingMore;
  final bool showLoadingPlaceholder;

  const _CartRecommendationsSection({
    this.title = 'Yuk dilihat lagi',
    required this.products,
    required this.loading,
    this.loadingMore = false,
    this.showLoadingPlaceholder = true,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty && (!loading || !showLoadingPlaceholder)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (loading && showLoadingPlaceholder)
          // Skeleton grid — feels lebih native dari spinner ditengah.
          const SkeletonProductGrid(count: 4, showAddToCart: true)
        else
          Column(
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Lebih tinggi untuk metadata hemat + rating/terjual.
                  childAspectRatio: 0.54,
                ),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ProductCard(
                    product: product,
                    onTap: () {
                      AppHaptics.tap();
                      Navigator.pushNamed(
                        context,
                        '/product-detail',
                        arguments: product,
                      );
                    },
                    showAddToCart: true,
                  );
                },
              ),
              if (loadingMore && showLoadingPlaceholder) ...[
                const SizedBox(height: 12),
                const SkeletonProductGrid(count: 2, showAddToCart: true),
              ],
            ],
          ),
      ],
    );
  }
}

/// Sticky checkout summary — solid surface, animated rupiah ticker.
/// Reference layout: "Total X item" + price + Checkout button 148w.
/// Disabled state saat tidak ada item selected.
class _CartSummaryBar extends StatelessWidget {
  final double grandTotal;
  final int selectedQuantity;
  final bool disabled;
  final VoidCallback onCheckout;

  const _CartSummaryBar({
    required this.grandTotal,
    required this.selectedQuantity,
    required this.disabled,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final checkoutLabel =
        disabled ? 'Checkout' : 'Checkout ($selectedQuantity)';
    return Material(
      color: NataloColors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: NataloColors.divider, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      disabled
                          ? 'Belum ada pilihan'
                          : 'Total $selectedQuantity item',
                      style: const TextStyle(
                        color: NataloColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Animated ticker untuk total — smooth tween saat
                    // user toggle selection atau update qty.
                    if (disabled)
                      const Text(
                        '-',
                        style: TextStyle(
                          color: NataloColors.textMuted,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    else
                      AnimatedRupiah(
                        value: grandTotal,
                        style: NataloTextStyles.totalPaymentPrice.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 178,
                height: 48,
                child: ElevatedButton(
                  onPressed: disabled ? null : onCheckout,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(checkoutLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Select all card ──
/// Checkbox + label + counter X/Y di kanan.
class _SelectAllCard extends StatelessWidget {
  final bool selected;
  final int totalProduct;
  final int selectedProduct;
  final VoidCallback onTap;

  const _SelectAllCard({
    required this.selected,
    required this.totalProduct,
    required this.selectedProduct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NataloColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NataloColors.border),
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                activeColor: _brandBlue,
                onChanged: (_) => onTap(),
              ),
              Expanded(
                child: Text(
                  selected ? 'Semua produk dipilih' : 'Pilih semua produk',
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$selectedProduct/$totalProduct',
                style: const TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cart empty state — match PWA app/cart/page.tsx EmptyCartShoppingCard:
/// - White card dengan Lottie animation + judul + body + CTA
/// - Section "Kamu sempat lihat-lihat ini" horizontal scroll di bawah (kalau ada)
/// - Section produk sistem di bawah (kalau ada)
class _EmptyCartState extends StatelessWidget {
  final ScrollController controller;
  final List<Product> recentlyViewed;
  final List<Product> bossProducts;
  final bool loadingBossProducts;
  final bool loadingMoreBossProducts;

  const _EmptyCartState({
    required this.controller,
    required this.recentlyViewed,
    required this.bossProducts,
    required this.loadingBossProducts,
    required this.loadingMoreBossProducts,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        0,
        14,
        0,
        28 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _EmptyCartCard(
          onExploreProduct: () {
            AppHaptics.tap();
            Navigator.pushReplacementNamed(context, '/products');
          },
        ),
        if (recentlyViewed.isNotEmpty) ...[
          const SizedBox(height: 28),
          _EmptyCartProductCarouselSection(
            title: 'Yuk dilihat lagi',
            products: recentlyViewed,
            onSeeAll: () => Navigator.pushNamed(context, '/products'),
            onProductTap: (product) {
              AppHaptics.tap();
              Navigator.pushNamed(
                context,
                '/product-detail',
                arguments: product,
              );
            },
            onAddToCart: (product) {
              cartStore.addProduct(product);
              AppToast.showCartAdded(
                context,
                '${product.title} masuk keranjang',
                actionLabel: 'Lihat Keranjang',
                onTap: () => Navigator.pushNamed(context, '/cart'),
              );
            },
          ),
        ],
        if (bossProducts.isNotEmpty) ...[
          const SizedBox(height: 28),
          _EmptyCartProductCarouselSection(
            title: 'Ayoo diborong bossku',
            products: bossProducts,
            onSeeAll: () => Navigator.pushNamed(context, '/products'),
            onProductTap: (product) {
              AppHaptics.tap();
              Navigator.pushNamed(
                context,
                '/product-detail',
                arguments: product,
              );
            },
            onAddToCart: (product) {
              cartStore.addProduct(product);
              AppToast.showCartAdded(
                context,
                '${product.title} masuk keranjang',
                actionLabel: 'Lihat Keranjang',
                onTap: () => Navigator.pushNamed(context, '/cart'),
              );
            },
          ),
        ] else if (loadingBossProducts || loadingMoreBossProducts) ...[
          const SizedBox(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SkeletonProductGrid(count: 2, showAddToCart: true),
          ),
        ],
      ],
    );
  }
}

class _EmptyCartCard extends StatelessWidget {
  final VoidCallback onExploreProduct;

  const _EmptyCartCard({required this.onExploreProduct});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFD9E7FF),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 245,
            width: double.infinity,
            child: Image.asset(
              'assets/illustrations/empty_cart_natalo_exact.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Keranjang kamu masih kosong',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              height: 1.18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Yuk pilih makanan, vitamin, pasir, atau perlengkapan\nfavorit untuk hewan kesayanganmu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onExploreProduct,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Jelajahi Produk',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCartProductCarouselSection extends StatelessWidget {
  final String title;
  final List<Product> products;
  final VoidCallback onSeeAll;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<Product> onAddToCart;

  const _EmptyCartProductCarouselSection({
    required this.title,
    required this.products,
    required this.onSeeAll,
    required this.onProductTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onSeeAll,
                behavior: HitTestBehavior.opaque,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lihat semua',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: _brandBlue,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 23,
                      color: _brandBlue,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 336,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final product = products[index];
              return _EmptyCartProductCard(
                product: product,
                onTap: () => onProductTap(product),
                onAddToCart: () => onAddToCart(product),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyCartProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const _EmptyCartProductCard({
    required this.product,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final discountPercent = productDiscountPercent(product);
    final savingsLabel = _cartSavingsLabel(product);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 178,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFE7EEF9),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: SizedBox(
                      height: 128,
                      width: double.infinity,
                      child: AppProductImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatRupiah(product.finalPrice),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (product.hasDiscount)
                    Text(
                      formatRupiah(product.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  const SizedBox(height: 6),
                  _CartRatingSoldRow(product: product),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _CartSavingsBadge(text: savingsLabel ?? ''),
                      ),
                      const SizedBox(width: 8),
                      _SmallCartButton(onTap: onAddToCart),
                    ],
                  ),
                ],
              ),
              if (discountPercent != null)
                Positioned(
                  top: 0,
                  left: 0,
                  child: _CartDiscountBadge(percent: discountPercent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartRatingSoldRow extends StatelessWidget {
  final Product product;

  const _CartRatingSoldRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating > 0;
    final hasSold = product.soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasRating) ...[
          const Icon(
            Icons.star_rounded,
            size: 15,
            color: Color(0xFFFBBF24),
          ),
          const SizedBox(width: 3),
          Text(
            product.rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 5),
          const Text(
            '|',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 5),
        ],
        if (hasSold)
          Expanded(
            child: Text(
              '${formatSoldCount(product.soldCount)} terjual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
      ],
    );
  }
}

class _CartDiscountBadge extends StatelessWidget {
  final int percent;

  const _CartDiscountBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    if (percent <= 0) return const SizedBox.shrink();

    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Text(
            '$percent%',
            style: const TextStyle(
              fontSize: 13,
              height: 1,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'OFF',
            style: TextStyle(
              fontSize: 9.5,
              height: 1,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSavingsBadge extends StatelessWidget {
  final String text;

  const _CartSavingsBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFC9D0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.confirmation_number_rounded,
            size: 14,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.8,
                fontWeight: FontWeight.w800,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallCartButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SmallCartButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFBFD5FF),
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.add_shopping_cart_rounded,
            size: 21,
            color: _brandBlue,
          ),
        ),
      ),
    );
  }
}

String? _cartSavingsLabel(Product product) {
  final voucherLabel = product.voucherPreview?.badgeLabel.trim();
  if (voucherLabel != null && voucherLabel.isNotEmpty) {
    return voucherLabel;
  }

  final label = productSavingsLabel(product);
  if (label == null) return null;
  return label.replaceFirst('Hemat ', 'Hemat s.d. ');
}
