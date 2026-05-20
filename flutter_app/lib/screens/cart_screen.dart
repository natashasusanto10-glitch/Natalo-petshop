import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../widgets/compact_commerce_product_card.dart';
import '../widgets/skeleton_product_card.dart';

const _brandBlue = NataloColors.nataloBlue;
const _discountRed = Color(0xFFE53958);
const _discountRedSoft = Color(0xFFFFF1F4);
const _discountRedBorder = Color(0xFFFFB8C8);
const _shippingGreen = Color(0xFF12A66A);
const _shippingGreenSoft = Color(0xFFECFDF3);
const _shippingGreenBorder = Color(0xFFA6F4C5);
const _voucherBarHeight = 64.0;
const _selectionRowHeight = 50.0;
// Shared cart chrome auto-hide config — selection row atas + voucher bar
// bawah pakai SAME duration + curve + state untuk gerakan 1:1 sinkron.
const _cartChromeIdleDelay = Duration(milliseconds: 180);
const _cartChromeAnimDuration = Duration(milliseconds: 220);
const _cartChromeAnimCurve = Curves.easeOutCubic;
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
  // Shared "cart chrome" state — controls BOTH selection row (top) +
  // voucher bar (bottom). Single state guarantees 1:1 synced animation:
  // saat user scroll, keduanya hide bareng; saat scroll stop, keduanya
  // muncul bareng dengan same duration + curve.
  Timer? _cartChromeTimer;
  bool _showCartChrome = true;
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
    _cartChromeTimer?.cancel();
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
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;

    if (cartStore.items.isNotEmpty && memberStore.isLoggedIn) {
      _hideCartChrome();
      _showCartChromeAfterStop();
    }

    if (_loadingBossProducts ||
        _loadingMoreBossProducts ||
        !_bossProductsHasMore) {
      return;
    }

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

  /// Detect apakah voucher ini termasuk kategori shipping (gratis ongkir).
  /// Cek 3 indicator dari backend response:
  ///   1. Sentinel code `__shipping_free__` (UI-side internal voucher
  ///      slot untuk free shipping system)
  ///   2. `isFreeShipping` getter (type == 'PUBLIC_FREE_SHIPPING')
  ///   3. `isShippingDiscount` getter (discountScope == 'SHIPPING')
  /// Method ini dipakai untuk pisahkan slot shipping voucher vs discount
  /// voucher di dual-slot voucher UI (1 customer + 1 shipping).
  bool _isCartShippingVoucher(MemberVoucher voucher) {
    return _isCartShippingVoucherData(voucher);
  }

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
        final manualVoucher =
            _findVoucherByCode(available, _manualVoucherCode!);
        if (manualVoucher != null && _isCartShippingVoucher(manualVoucher)) {
          manualStillEligible = true;
          nextShipping = true;
          nextDiscount = bestDiscount;
        } else if (manualVoucher != null) {
          manualStillEligible = true;
          nextDiscount = manualVoucher;
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
    final eligible = vouchers
        .where(
          (voucher) => voucher.discount > 0 && !_isCartShippingVoucher(voucher),
        )
        .toList();
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

  void _hideCartChrome() {
    _cartChromeTimer?.cancel();
    if (!_showCartChrome) return;
    setState(() => _showCartChrome = false);
  }

  void _showCartChromeAfterStop() {
    _cartChromeTimer?.cancel();
    _cartChromeTimer = Timer(_cartChromeIdleDelay, () {
      if (!mounted || _showCartChrome) return;
      setState(() => _showCartChrome = true);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _hideCartChrome();
      return false;
    }

    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _hideCartChrome();
      // Tokopedia-like: reset timer setiap frame scroll. Bar muncul sendiri
      // setelah list benar-benar idle, tanpa user perlu tap layar lagi.
      _showCartChromeAfterStop();
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _showCartChromeAfterStop();
      } else {
        _hideCartChrome();
      }
      return false;
    }

    if (notification is ScrollEndNotification) {
      _showCartChromeAfterStop();
    }
    return false;
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
        selectedShippingCode:
            _appliedShippingVoucher && _isManualVoucherSelected
                ? _manualVoucherCode
                : null,
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
      _manualVoucherCode = picked.discountVoucher?.code ?? picked.shippingCode;
      _appliedDiscountVoucher = picked.discountVoucher;
      _appliedShippingVoucher =
          picked.shippingSelected && _shippingVoucherEligible;
    });
  }

  // _syncCart dihapus — cloud sync icon di-remove dari AppBar (per
  // simplified design). Cart auto-sync sudah via login flow.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Solid surface bg — override theme transparency yang bikin header
      // & content nampak semi-transparent / kurang sharp (spec: header
      // harus solid, tidak terkena efek glass/blur dari layer lain).
      backgroundColor: NataloColors.surface,
      // Custom title dengan count subtitle — match PWA cart header
      // "Keranjang\n0 jenis produk (0 item)".
      // AppBar override eksplisit ke putih solid (theme global pakai
      // surface 0.90 = semi-transparent yang inherit ke cart → header
      // jadi kurang tajam). Border bawah tipis untuk crisp visual edge.
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFE5EAF2), width: 1),
        ),
        title: const Text('Keranjang'),
        actions: [
          // Wishlist heart icon — replace dari trash/kosongkan action lama.
          // Trash icon sekarang muncul di selection row di bawah header,
          // bukan di AppBar. Pattern match Tokopedia / e-commerce modern.
          IconButton(
            tooltip: 'Wishlist',
            onPressed: () => Navigator.pushNamed(context, '/wishlist'),
            icon: const Icon(Icons.favorite_border_rounded),
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

          final showVoucherArea = memberStore.isLoggedIn;

          // Column body — auto-hide chrome (top + bottom) sandwich main
          // ListView. Selection row + voucher bar share `_showCartChrome`
          // state untuk gerakan 1:1 sinkron saat user scroll. Checkout
          // bar di paling bawah, SELALU visible (tidak ikut auto-hide).
          return Column(
            children: [
              // ── Auto-hide top: selection row compact ──
              ClipRect(
                child: AnimatedContainer(
                  height: _showCartChrome ? _selectionRowHeight : 0,
                  duration: _cartChromeAnimDuration,
                  curve: _cartChromeAnimCurve,
                  child: AnimatedSlide(
                    offset: _showCartChrome ? Offset.zero : const Offset(0, -1),
                    duration: _cartChromeAnimDuration,
                    curve: _cartChromeAnimCurve,
                    child: AnimatedOpacity(
                      opacity: _showCartChrome ? 1 : 0,
                      duration: _cartChromeAnimDuration,
                      curve: _cartChromeAnimCurve,
                      child: IgnorePointer(
                        ignoring: !_showCartChrome,
                        child: _CartSelectedRow(
                          selectedCount: _selectedItems.length,
                          onDeleteSelected: _selectedItems.isEmpty
                              ? null
                              : _confirmRemoveSelected,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ── Scrollable content (cart items + recommendations) ──
              Expanded(
                child: Listener(
                  onPointerDown: (_) => _hideCartChrome(),
                  onPointerMove: (_) => _hideCartChrome(),
                  onPointerUp: (_) => _showCartChromeAfterStop(),
                  onPointerCancel: (_) => _showCartChromeAfterStop(),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      children: [
                        // Cart items dengan checkbox per item.
                        for (var i = 0; i < items.length; i++) ...[
                          _CartItemCard(
                            item: items[i],
                            index: i,
                            selected: _selectedIds.contains(items[i].key),
                            onToggleSelected: () => _toggleItem(items[i].key),
                          ),
                          // Divider indented dari kiri checkbox — start setelah
                          // checkbox area supaya garis tidak full-width.
                          // Tokopedia style: divider sejajar dengan image kiri.
                          if (i < items.length - 1)
                            const Padding(
                              padding: EdgeInsets.only(left: 42),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFFEEF2F6),
                              ),
                            )
                          else
                            const SizedBox(height: 8),
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
              ),
              // ── Auto-hide bottom: voucher bar ──
              if (showVoucherArea)
                ClipRect(
                  child: AnimatedContainer(
                    height: _showCartChrome ? _voucherBarHeight : 0,
                    duration: _cartChromeAnimDuration,
                    curve: _cartChromeAnimCurve,
                    child: AnimatedSlide(
                      offset:
                          _showCartChrome ? Offset.zero : const Offset(0, 1),
                      duration: _cartChromeAnimDuration,
                      curve: _cartChromeAnimCurve,
                      child: AnimatedOpacity(
                        opacity: _showCartChrome ? 1 : 0,
                        duration: _cartChromeAnimDuration,
                        curve: _cartChromeAnimCurve,
                        child: IgnorePointer(
                          ignoring: !_showCartChrome,
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
              // ── Checkout bar SELALU visible (tidak ikut auto-hide) ──
              _CartSummaryBar(
                grandTotal: _grandTotal,
                totalSaving: _totalVoucherSaving,
                selectedQuantity: _selectedQuantity,
                disabled: _selectedItems.isEmpty,
                onCheckout: _goToCheckout,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact selection row di atas list — replace _SelectAllCard yang besar.
/// Layout: "1 produk terpilih" di kiri, trash icon di kanan.
/// Height 50, padding horizontal 20, border bottom tipis untuk crisp edge.
/// Trash icon disabled saat selectedCount = 0. Tap trash → confirm dialog.
class _CartSelectedRow extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onDeleteSelected;

  const _CartSelectedRow({
    required this.selectedCount,
    required this.onDeleteSelected,
  });

  String _selectedText(int count) {
    if (count <= 0) return 'Belum ada produk terpilih';
    if (count == 1) return '1 produk terpilih';
    return '$count produk terpilih';
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Container(
      height: _selectionRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8EDF5), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedText(selectedCount),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: hasSelection
                    ? const Color(0xFF101828)
                    : const Color(0xFF6B7280),
              ),
            ),
          ),
          IconButton(
            onPressed: hasSelection ? onDeleteSelected : null,
            tooltip: 'Hapus terpilih',
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 22,
              color: hasSelection
                  ? const Color(0xFF101828)
                  : const Color(0xFFB8C0CC),
            ),
            splashRadius: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ],
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

  /// Open bottom sheet variant picker — fetch full product (with all
  /// variants), user pilih varian baru, swap di cart.
  Future<void> _openVariantSheet(BuildContext context) async {
    AppHaptics.tap();
    final picked = await showModalBottomSheet<ProductVariant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CartVariantPickerSheet(
        cartItem: item,
      ),
    );
    if (picked == null) return;
    // Variant swap = remove old cart item + add product dengan variant
    // baru, qty SAMA seperti sebelumnya. cartStore.addItem auto-merge
    // kalau variantId sudah ada di cart (increment qty existing).
    await cartStore.remove(item.key);
    await cartStore.addProduct(
      item.product,
      variant: picked,
      variantLabel: picked.sku ?? _composeVariantLabel(item.product, picked),
      quantity: item.quantity,
    );
  }

  /// Compose label varian "Hitam, S" dari variant.optionIds × product
  /// variantAttrs. Fallback ke SKU kalau attrs tidak lengkap.
  String _composeVariantLabel(Product product, ProductVariant variant) {
    final labels = <String>[];
    for (final attr in product.variantAttrs) {
      for (final opt in attr.options) {
        if (variant.optionIds.contains(opt.id)) {
          labels.add(opt.value);
          break;
        }
      }
    }
    if (labels.isEmpty) return variant.sku ?? '';
    return labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final price = item.effectivePrice;
    final regular = item.product.price;
    final hasDiscount = regular > price;
    final discountPercent =
        hasDiscount ? (((regular - price) / regular) * 100).round() : 0;
    final hasVariants = item.product.hasVariants;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: Duration(milliseconds: 220 + (index * 35).clamp(0, 180)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 24),
            child: child,
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
          color: const Color(0xFFEF4444),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        // Compact marketplace-style — no big rounded card, thin divider
        // antar item (handled di parent ListView/Column).
        child: Container(
          color: Colors.white,
          // Padding kiri ringkas (4px) supaya checkbox nempel kiri ala
          // Tokopedia. Vertical 12 (sedikit lebih ringkas dari 14).
          padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox kiri.
              Checkbox(
                value: selected,
                activeColor: _brandBlue,
                onChanged: (_) => onToggleSelected(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              // Product image — soft bg, no border. Tokopedia size ~64px,
              // radius kecil supaya feels marketplace native.
              InkWell(
                onTap: () => _openProductDetail(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AppProductImage(
                    imageUrl: item.product.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Detail column kanan — name, variant chip, price + stepper row.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nama produk only — NO brand/category. Max 2 lines.
                    InkWell(
                      onTap: () => _openProductDetail(context),
                      child: Text(
                        item.product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF17202A),
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // Variant chip — HANYA kalau product punya variants.
                    // Tap → buka bottom sheet variant picker untuk ganti.
                    if (hasVariants && item.variantLabel != null) ...[
                      const SizedBox(height: 8),
                      _VariantChipDropdown(
                        label: item.variantLabel!,
                        onTap: () => _openVariantSheet(context),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Row: price + stepper sejajar horizontal.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      formatRupiah(price),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: hasDiscount
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF111827),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (hasDiscount) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$discountPercent%',
                                        style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (hasDiscount) ...[
                                const SizedBox(height: 2),
                                Text(
                                  formatRupiah(regular),
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.lineThrough,
                                  ),
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

/// Variant chip dengan icon ▼ — soft gray pill. Hanya muncul kalau
/// product.hasVariants true. Tap → onTap callback (open variant picker
/// bottom sheet di parent).
class _VariantChipDropdown extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _VariantChipDropdown({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet untuk ganti variant produk di cart. Fetch full product
/// data (semua variants + attrs) lewat productService.fetchProductBySlug,
/// display variant chips, user select → return ProductVariant ke parent
/// untuk swap di cart.
class _CartVariantPickerSheet extends StatefulWidget {
  final CartItem cartItem;

  const _CartVariantPickerSheet({required this.cartItem});

  @override
  State<_CartVariantPickerSheet> createState() =>
      _CartVariantPickerSheetState();
}

class _CartVariantPickerSheetState extends State<_CartVariantPickerSheet> {
  Product? _fullProduct;
  bool _loading = true;
  String? _error;
  final Map<String, String> _selectedOptions = {};

  @override
  void initState() {
    super.initState();
    _loadFullProduct();
  }

  Future<void> _loadFullProduct() async {
    try {
      // Re-fetch product full untuk dapat variantAttrs + variants lengkap.
      // CartItem.product mungkin partial (dari listing endpoint yang
      // tidak include semua varian untuk hemat payload).
      final slug = widget.cartItem.product.slug;
      final result = await productService.fetchProductBySlug(slug);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'Produk tidak ditemukan.';
        });
        return;
      }
      // Pre-select current variant options kalau ada.
      final currentVariant = widget.cartItem.variant;
      if (currentVariant != null) {
        for (final attr in result.variantAttrs) {
          for (final opt in attr.options) {
            if (currentVariant.optionIds.contains(opt.id)) {
              _selectedOptions[attr.id] = opt.id;
              break;
            }
          }
        }
      }
      setState(() {
        _fullProduct = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memuat varian. Coba lagi.';
      });
    }
  }

  /// Cari variant yang match dengan selected options. Return null kalau
  /// belum lengkap atau combination tidak exist.
  ProductVariant? get _matchedVariant {
    final product = _fullProduct;
    if (product == null) return null;
    if (_selectedOptions.length < product.variantAttrs.length) return null;
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      final matches = product.variantAttrs.every((attr) {
        final selectedOpt = _selectedOptions[attr.id];
        return selectedOpt != null && variant.optionIds.contains(selectedOpt);
      });
      if (matches) return variant;
    }
    return null;
  }

  bool _isOptionAvailable(String attrId, String optionId) {
    final product = _fullProduct;
    if (product == null) return false;
    // Cek apakah ada minimal 1 variant active yang punya combination ini
    // + selected options lain. Disable option yang tidak ada kombinasinya.
    final otherSelected = Map<String, String>.from(_selectedOptions);
    otherSelected.remove(attrId);
    for (final variant in product.variants) {
      if (!variant.isActive) continue;
      if (!variant.optionIds.contains(optionId)) continue;
      final matchesOthers = otherSelected.entries
          .every((entry) => variant.optionIds.contains(entry.value));
      if (matchesOthers) return true;
    }
    return false;
  }

  void _onSelect(String attrId, String optionId) {
    AppHaptics.selection();
    setState(() {
      _selectedOptions[attrId] = optionId;
    });
  }

  void _confirm() {
    final variant = _matchedVariant;
    if (variant == null) return;
    AppHaptics.tap();
    Navigator.pop(context, variant);
  }

  @override
  Widget build(BuildContext context) {
    final variant = _matchedVariant;
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Variasi Produk',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFF6B7280),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(child: _buildBody()),
              if (_fullProduct != null && _error == null)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Harga varian',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                variant != null
                                    ? formatRupiah(variant.price.toDouble())
                                    : '—',
                                style: const TextStyle(
                                  color: _brandBlue,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: variant != null ? _confirm : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandBlue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFCBD5E1),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            child: const Text('Pilih'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null || _fullProduct == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error ?? 'Produk tidak ditemukan.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final product = _fullProduct!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        for (final attr in product.variantAttrs) ...[
          Text(
            attr.name,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attr.options.map((opt) {
              final selected = _selectedOptions[attr.id] == opt.id;
              final available = _isOptionAvailable(attr.id, opt.id);
              return GestureDetector(
                onTap: available ? () => _onSelect(attr.id, opt.id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _brandBlue.withValues(alpha: 0.10)
                        : available
                            ? Colors.white
                            : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: selected
                          ? _brandBlue
                          : available
                              ? const Color(0xFFD1D5DB)
                              : const Color(0xFFE5E7EB),
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Text(
                    opt.value,
                    style: TextStyle(
                      color: selected
                          ? _brandBlue
                          : available
                              ? const Color(0xFF374151)
                              : const Color(0xFFB8C0CC),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ],
      ],
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

bool _isCartShippingVoucherData(MemberVoucher voucher) {
  if (voucher.code == _shippingVoucherCode) return true;
  if (voucher.isFreeShipping || voucher.isShippingDiscount) return true;

  final searchableText = [
    voucher.code,
    voucher.title,
    voucher.description,
  ].join(' ').toLowerCase();

  return searchableText.contains('ongkir') ||
      searchableText.contains('gratis kirim') ||
      searchableText.contains('free shipping');
}

String _cartShippingVoucherSubtitle(
    MemberVoucher voucher, int fallbackDiscount) {
  final description = voucher.description.trim();
  if (description.isNotEmpty && !description.toLowerCase().startsWith('http')) {
    return description;
  }

  if (voucher.discount > 0) {
    return 'Potongan ongkir ${formatRupiah(voucher.discount)}';
  }
  if (fallbackDiscount > 0) {
    return 'Potongan ongkir ${formatRupiah(fallbackDiscount)}';
  }

  return 'Gratis ongkir untuk pesanan ini';
}

bool _isCartShippingVoucher(MemberVoucher voucher) {
  return _isCartShippingVoucherData(voucher);
}

MemberVoucher? _findSheetVoucherByCode(
  List<MemberVoucher> vouchers,
  String code,
) {
  for (final voucher in vouchers) {
    if (voucher.code == code) return voucher;
  }
  return null;
}

class _CartVoucherChoice {
  final String? shippingCode;
  final MemberVoucher? discountVoucher;
  final bool shippingSelected;
  final bool remove;

  const _CartVoucherChoice._({
    this.shippingCode,
    this.discountVoucher,
    this.shippingSelected = false,
    this.remove = false,
  });

  factory _CartVoucherChoice.combined({
    required MemberVoucher? discountVoucher,
    required bool shippingSelected,
    String? shippingCode,
  }) {
    return _CartVoucherChoice._(
      shippingCode: shippingCode,
      discountVoucher: discountVoucher,
      shippingSelected: shippingSelected,
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
    final leadingColor = hasShipping
        ? _shippingGreen
        : hasDiscount
            ? _discountRed
            : _brandBlue;
    final leadingBackground = hasShipping
        ? _shippingGreenSoft
        : hasDiscount
            ? _discountRedSoft
            : const Color(0xFFEAF5FF);
    final leadingBorder = hasShipping
        ? _shippingGreenBorder
        : hasDiscount
            ? _discountRedBorder
            : const Color(0xFFBFDBFE);
    final leadingIcon = hasShipping
        ? Icons.local_shipping_outlined
        : hasDiscount
            ? Icons.local_offer_rounded
            : Icons.confirmation_number_rounded;
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
                    color: leadingBackground,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: leadingBorder),
                  ),
                  child: Icon(
                    leadingIcon,
                    color: leadingColor,
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
                _VoucherBenefitChips(
                  hasShipping: hasShipping,
                  shippingText: 'Gratis Ongkir',
                  hasDiscount: hasDiscount,
                  discountText: '-${formatRupiah(discountAmount)}',
                  loading: loading,
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

class _VoucherBenefitChips extends StatelessWidget {
  final bool hasShipping;
  final String shippingText;
  final bool hasDiscount;
  final String discountText;
  final bool loading;

  const _VoucherBenefitChips({
    required this.hasShipping,
    required this.shippingText,
    required this.hasDiscount,
    required this.discountText,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (hasShipping) {
      chips.add(
        _VoucherMiniChip(
          text: shippingText,
          color: _shippingGreen,
          background: _shippingGreenSoft,
          border: _shippingGreenBorder,
          icon: Icons.local_shipping_outlined,
        ),
      );
    }
    if (hasDiscount) {
      if (chips.isNotEmpty) chips.add(const SizedBox(width: 6));
      chips.add(
        _VoucherMiniChip(
          text: discountText,
          color: _discountRed,
          background: _discountRedSoft,
          border: _discountRedBorder,
          icon: Icons.local_offer_rounded,
        ),
      );
    }
    if (chips.isEmpty) {
      chips.add(
        _VoucherMiniChip(
          text: loading ? 'Cek...' : 'Pilih',
          color: _brandBlue,
          background: const Color(0xFFEAF5FF),
          border: const Color(0xFFBFDBFE),
          icon: Icons.confirmation_number_rounded,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 178),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(mainAxisSize: MainAxisSize.min, children: chips),
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
  final String? selectedShippingCode;
  final bool shippingSelected;
  final bool isManual;
  final bool loading;

  const _CartVoucherSheet({
    required this.availableDiscounts,
    required this.unavailableDiscounts,
    required this.shippingEligible,
    required this.shippingDiscount,
    required this.selectedDiscountCode,
    required this.selectedShippingCode,
    required this.shippingSelected,
    required this.isManual,
    required this.loading,
  });

  @override
  State<_CartVoucherSheet> createState() => _CartVoucherSheetState();
}

class _CartVoucherSheetState extends State<_CartVoucherSheet> {
  String? _selectedShippingCode;
  MemberVoucher? _selectedDiscount;

  @override
  void initState() {
    super.initState();
    if (widget.selectedDiscountCode != null) {
      final selectedVoucher = _findSheetVoucherByCode(
        widget.availableDiscounts,
        widget.selectedDiscountCode!,
      );
      if (selectedVoucher != null && _isCartShippingVoucher(selectedVoucher)) {
        _selectedShippingCode = selectedVoucher.code;
      } else {
        for (final voucher in widget.availableDiscounts) {
          if (voucher.code == widget.selectedDiscountCode) {
            _selectedDiscount = voucher;
            break;
          }
        }
      }
    }

    if (widget.shippingSelected) {
      _selectedShippingCode ??=
          widget.selectedShippingCode ?? _firstAvailableShippingCode();
    }
  }

  String? _firstAvailableShippingCode() {
    for (final voucher in widget.availableDiscounts) {
      if (_isCartShippingVoucher(voucher)) return voucher.code;
    }
    return widget.shippingEligible ? _shippingVoucherCode : null;
  }

  void _pickDiscount(MemberVoucher voucher) {
    setState(() {
      if (_selectedDiscount?.code == voucher.code) {
        _selectedDiscount = null;
      } else {
        _selectedDiscount = voucher;
      }
    });
  }

  void _pickShipping([String? code]) {
    final nextCode = code ?? _shippingVoucherCode;
    setState(() {
      _selectedShippingCode =
          _selectedShippingCode == nextCode ? null : nextCode;
    });
  }

  void _applySelection() {
    Navigator.pop(
      context,
      _CartVoucherChoice.combined(
        discountVoucher: _selectedDiscount,
        shippingSelected: _selectedShippingCode != null,
        shippingCode: _selectedShippingCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final availableShippingVouchers =
        widget.availableDiscounts.where(_isCartShippingVoucher).toList();
    final availableProductVouchers = widget.availableDiscounts
        .where((voucher) => !_isCartShippingVoucher(voucher))
        .toList();
    final unavailableShippingVouchers =
        widget.unavailableDiscounts.where(_isCartShippingVoucher).toList();
    final unavailableProductVouchers = widget.unavailableDiscounts
        .where((voucher) => !_isCartShippingVoucher(voucher))
        .toList();
    final showSyntheticShipping =
        widget.shippingEligible && availableShippingVouchers.isEmpty;
    final hasAnyVoucher = showSyntheticShipping ||
        availableShippingVouchers.isNotEmpty ||
        availableProductVouchers.isNotEmpty;

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
                    if (showSyntheticShipping) ...[
                      _CartVoucherCard(
                        title: 'Gratis Ongkir',
                        subtitle:
                            'Potongan ongkir ${formatRupiah(widget.shippingDiscount)}',
                        badge: 'Ongkir',
                        icon: Icons.local_shipping_outlined,
                        accent: _shippingGreen,
                        background: _shippingGreenSoft,
                        border: _shippingGreenBorder,
                        selected: _selectedShippingCode == _shippingVoucherCode,
                        enabled: true,
                        onTap: _pickShipping,
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final voucher in availableShippingVouchers) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: _cartShippingVoucherSubtitle(
                          voucher,
                          widget.shippingDiscount,
                        ),
                        badge: 'Ongkir',
                        trailing: voucher.discount > 0
                            ? formatRupiah(voucher.discount)
                            : null,
                        icon: Icons.local_shipping_outlined,
                        accent: _shippingGreen,
                        background: _shippingGreenSoft,
                        border: _shippingGreenBorder,
                        selected: _selectedShippingCode == voucher.code,
                        enabled: true,
                        onTap: () => _pickShipping(voucher.code),
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final voucher in availableProductVouchers) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: voucher.description,
                        badge: 'Diskon',
                        trailing: formatRupiah(voucher.discount),
                        icon: Icons.local_offer_rounded,
                        accent: _discountRed,
                        background: _discountRedSoft,
                        border: _discountRedBorder,
                        selected: _selectedDiscount?.code == voucher.code,
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
                    if (unavailableShippingVouchers.isNotEmpty ||
                        unavailableProductVouchers.isNotEmpty) ...[
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
                      for (final voucher in unavailableShippingVouchers) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              _cartShippingVoucherSubtitle(
                                voucher,
                                widget.shippingDiscount,
                              ),
                          badge: 'Ongkir',
                          trailing: voucher.discount > 0
                              ? formatRupiah(voucher.discount)
                              : null,
                          icon: Icons.local_shipping_outlined,
                          accent: _shippingGreen,
                          background: const Color(0xFFF8FAFC),
                          border: const Color(0xFFE2E8F0),
                          selected: false,
                          enabled: false,
                          onTap: null,
                        ),
                        const SizedBox(height: 10),
                      ],
                      for (final voucher in unavailableProductVouchers) ...[
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
                      onPressed: _selectedDiscount == null &&
                              _selectedShippingCode == null
                          ? null
                          : _applySelection,
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
                  return CompactCommerceProductCard(
                    product: product,
                    onTap: () {
                      AppHaptics.tap();
                      Navigator.pushNamed(
                        context,
                        '/product-detail',
                        arguments: product,
                      );
                    },
                    onAddToCart: () {
                      AppHaptics.success();
                      cartStore.addProduct(product);
                      AppToast.showCartAdded(
                        context,
                        '${product.title} masuk keranjang',
                      );
                    },
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
/// Reference layout: price + total saving + Checkout button 148w.
/// Disabled state saat tidak ada item selected.
class _CartSummaryBar extends StatelessWidget {
  final double grandTotal;
  final double totalSaving;
  final int selectedQuantity;
  final bool disabled;
  final VoidCallback onCheckout;

  const _CartSummaryBar({
    required this.grandTotal,
    required this.totalSaving,
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
                    // Animated ticker untuk total — smooth tween saat
                    // user toggle selection atau update qty.
                    if (disabled)
                      const Text(
                        'Belum ada pilihan',
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
                    if (!disabled && totalSaving > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Total Hemat ${formatRupiah(totalSaving)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _discountRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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
              return CompactCommerceProductCard(
                product: product,
                width: 178,
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
