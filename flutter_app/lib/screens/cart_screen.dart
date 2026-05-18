import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../screens/checkout_screen.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../state/recently_viewed_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_product_card.dart';

// ── Private color tokens ──
// Sebelumnya inline literal — extract jadi const supaya konsisten antar widget
// di file ini. Selaras dengan NataloColors palette.
const _brandBlue = NataloColors.primary;

/// Animated Rupiah display — angka berubah dengan smooth transition.
/// Dipakai di sticky bottom bar checkout supaya update total feel responsive.
class AnimatedRupiah extends StatelessWidget {
  final int amount;
  final TextStyle? style;
  final Duration duration;

  const AnimatedRupiah({
    super.key,
    required this.amount,
    this.style,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        formatRupiah(amount),
        key: ValueKey(amount),
        style: style,
      ),
    );
  }
}

/// Cart screen — premium cart list, edit qty, remove with undo, recommendations,
/// and selected-item checkout.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedKeys = <String>{};
  final Set<String> _knownCartKeys = <String>{};

  List<Product> _bossProducts = const [];
  bool _loadingBossProducts = true;
  bool _loadingMoreBossProducts = false;
  int _bossProductLimit = 12;

  late final Listenable _pageListenable;

  @override
  void initState() {
    super.initState();
    _pageListenable = Listenable.merge([cartStore, recentlyViewedStore]);
    cartStore.addListener(_handleCartChanged);
    _scrollController.addListener(_handleScroll);
    _syncSelectedKeys(selectNewItems: true);
    _loadBossProducts();
  }

  @override
  void dispose() {
    cartStore.removeListener(_handleCartChanged);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleCartChanged() {
    final changed = _syncSelectedKeys(selectNewItems: true);
    if (changed && mounted) setState(() {});
  }

  bool _syncSelectedKeys({required bool selectNewItems}) {
    final cartKeys = cartStore.items.map((item) => item.key).toSet();
    final beforeSelected = Set<String>.of(_selectedKeys);
    final beforeKnown = Set<String>.of(_knownCartKeys);

    _selectedKeys.removeWhere((key) => !cartKeys.contains(key));
    if (selectNewItems) {
      for (final key in cartKeys.difference(_knownCartKeys)) {
        _selectedKeys.add(key);
      }
    }

    _knownCartKeys
      ..clear()
      ..addAll(cartKeys);

    return beforeSelected.length != _selectedKeys.length ||
        !beforeSelected.containsAll(_selectedKeys) ||
        beforeKnown.length != _knownCartKeys.length ||
        !beforeKnown.containsAll(_knownCartKeys);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loadingBossProducts ||
        _loadingMoreBossProducts) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 420) {
      _loadBossProducts(loadMore: true);
    }
  }

  Future<void> _loadBossProducts({bool loadMore = false}) async {
    if (loadMore && _loadingMoreBossProducts) return;
    if (!loadMore &&
        _loadingBossProducts == false &&
        _bossProducts.isNotEmpty) {
      return;
    }

    setState(() {
      if (loadMore) {
        _loadingMoreBossProducts = true;
        _bossProductLimit += 8;
      } else {
        _loadingBossProducts = true;
      }
    });

    final viewedIds = recentlyViewedStore.items.map((p) => p.id).toList();
    final excludeIds = cartStore.items.map((item) => item.product.id).toList();
    var products = await productService.fetchRecommendations(
      viewedIds: viewedIds,
      excludeIds: excludeIds,
      limit: _bossProductLimit,
    );
    if (products.isEmpty) {
      products = await productService.fetchAll(limit: _bossProductLimit);
    }

    final excludeSet = excludeIds.toSet();
    final unique = <String, Product>{};
    for (final product in products) {
      if (product.id.isEmpty || excludeSet.contains(product.id)) continue;
      unique.putIfAbsent(product.id, () => product);
    }

    if (!mounted) return;
    setState(() {
      _bossProducts = unique.values.toList(growable: false);
      _loadingBossProducts = false;
      _loadingMoreBossProducts = false;
    });
  }

  List<CartItem> get _selectedItems {
    return cartStore.items
        .where((item) => _selectedKeys.contains(item.key))
        .toList(growable: false);
  }

  int get _selectedQuantity {
    return _selectedItems.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  double get _selectedTotal {
    return _selectedItems.fold<double>(0, (sum, item) => sum + item.lineTotal);
  }

  void _toggleSelectAll() {
    AppHaptics.tap();
    setState(() {
      final keys = cartStore.items.map((item) => item.key).toSet();
      if (_selectedKeys.length == keys.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(keys);
      }
    });
  }

  void _toggleItem(String key) {
    AppHaptics.tap();
    setState(() {
      if (!_selectedKeys.remove(key)) {
        _selectedKeys.add(key);
      }
    });
  }

  Future<void> _openDeleteSelectedDialog() async {
    final items = _selectedItems.isNotEmpty ? _selectedItems : cartStore.items;
    if (items.isEmpty) return;

    final quantity = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _CartDeleteConfirmDialog(
        count: items.length,
        quantity: quantity,
      ),
    );
    if (confirmed != true || !mounted) return;
    _removeItemsWithUndo(items);
  }

  void _removeItemsWithUndo(List<CartItem> items) {
    final currentItems = cartStore.items;
    final removed = <({CartItem item, int index})>[];
    for (final item in items) {
      final index =
          currentItems.indexWhere((cartItem) => cartItem.key == item.key);
      removed.add((item: item, index: index < 0 ? currentItems.length : index));
      unawaited(cartStore.remove(item.key));
    }

    setState(() {
      for (final item in items) {
        _selectedKeys.remove(item.key);
      }
    });

    _showCartDeleteSnackBar(
      context,
      message: 'Produk telah dihapus',
      onUndo: () => unawaited(_restoreRemovedItems(removed)),
    );
  }

  Future<void> _restoreRemovedItems(
      List<({CartItem item, int index})> items) async {
    final ordered = [...items]..sort((a, b) => a.index.compareTo(b.index));
    for (final removed in ordered) {
      await cartStore.restore(removed.item, index: removed.index);
    }
  }

  void _openCheckout() {
    final items = _selectedItems;
    if (items.isEmpty) {
      AppHaptics.warning();
      return;
    }
    AppHaptics.impact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(items: items),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Keranjang'),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          AnimatedBuilder(
            animation: cartStore,
            builder: (context, _) {
              if (cartStore.isEmpty) return const SizedBox(width: 48);
              return IconButton(
                tooltip: 'Hapus produk',
                onPressed: _openDeleteSelectedDialog,
                icon: const Icon(Icons.delete_outline_rounded),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _pageListenable,
        builder: (context, _) {
          if (cartStore.isEmpty) {
            return _EmptyCartState(
              controller: _scrollController,
              recentlyViewed: recentlyViewedStore.items,
              bossProducts: _bossProducts,
              loadingBossProducts: _loadingBossProducts,
              loadingMoreBossProducts: _loadingMoreBossProducts,
            );
          }
          final items = cartStore.items;
          final allSelected =
              items.isNotEmpty && _selectedKeys.length == items.length;
          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 118),
            children: [
              _SelectAllCard(
                selected: allSelected,
                totalProduct: items.length,
                selectedProduct: _selectedKeys.length,
                onTap: _toggleSelectAll,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < items.length; i++) ...[
                _CartItemCard(
                  item: items[i],
                  index: i,
                  selected: _selectedKeys.contains(items[i].key),
                  onToggleSelected: () => _toggleItem(items[i].key),
                ),
                const SizedBox(height: 12),
              ],
              if (recentlyViewedStore.items.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CartRecommendationsSection(
                  title: 'Ayo dilihat lagi',
                  products: recentlyViewedStore.items.take(6).toList(),
                  loading: false,
                  showLoadingPlaceholder: false,
                ),
              ],
              const SizedBox(height: 22),
              _CartRecommendationsSection(
                title: 'Ayoo diborong bossku',
                products: _bossProducts,
                loading: _loadingBossProducts,
                loadingMore: _loadingMoreBossProducts,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: cartStore,
        builder: (context, _) {
          if (cartStore.isEmpty) return const SizedBox.shrink();
          return _CartSummaryBar(
            grandTotal: _selectedTotal,
            selectedQuantity: _selectedQuantity,
            disabled: _selectedItems.isEmpty,
            onCheckout: _openCheckout,
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
    this.title = 'Ayo dilihat lagi',
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
                        amount: grandTotal.round(),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ── Empty state card dengan illustration multi-pet emoji ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDDE8F8)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF111111).withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              const _EmptyCartIllustration(),
              const SizedBox(height: 14),
              const Text(
                'Keranjang kamu masih kosong',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF17202A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Yuk pilih makanan, vitamin, pasir, atau perlengkapan favorit untuk hewan kesayanganmu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Produk yang kamu tambahkan akan muncul di sini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  AppHaptics.tap();
                  Navigator.pushReplacementNamed(context, '/products');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  'Jelajahi Produk',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (recentlyViewed.isNotEmpty) ...[
          const SizedBox(height: 22),
          const _SectionHeader(
            title: 'Ayo dilihat lagi',
            actionLabel: 'Lihat semua',
            actionRoute: '/products',
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 260,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: recentlyViewed.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final product = recentlyViewed[index];
                return SizedBox(
                  width: 150,
                  child: ProductCard(
                    product: product,
                    onTap: () {
                      AppHaptics.tap();
                      Navigator.pushNamed(
                        context,
                        '/product-detail',
                        arguments: product,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
        if (bossProducts.isNotEmpty) ...[
          const SizedBox(height: 22),
          _CartRecommendationsSection(
            title: 'Ayoo diborong bossku',
            products: bossProducts,
            loading: loadingBossProducts,
            loadingMore: loadingMoreBossProducts,
            showLoadingPlaceholder: false,
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final String actionRoute;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.actionRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
        TextButton.icon(
          onPressed: () => Navigator.pushNamed(context, actionRoute),
          icon: const SizedBox.shrink(),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                actionLabel,
                style: const TextStyle(
                  color: _brandBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _brandBlue,
                size: 18,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Illustration empty cart — kumpulan emoji pet di ring dengan cart icon
/// di tengah. Native Flutter (no extra asset), match feel PWA illustration.
class _EmptyCartIllustration extends StatelessWidget {
  const _EmptyCartIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Background blob gradient halus
          Container(
            height: 130,
            width: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _brandBlue.withValues(alpha: 0.06),
                  const Color(0xFFFEF3F2).withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          // Pet emojis di sekeliling
          const Positioned(
            left: 8,
            top: 18,
            child: Text('🐱', style: TextStyle(fontSize: 38)),
          ),
          const Positioned(
            top: 0,
            child: Text('🐶', style: TextStyle(fontSize: 44)),
          ),
          const Positioned(
            right: 8,
            top: 18,
            child: Text('🐰', style: TextStyle(fontSize: 38)),
          ),
          const Positioned(
            left: 30,
            bottom: 4,
            child: Text('🐠', style: TextStyle(fontSize: 30)),
          ),
          const Positioned(
            right: 28,
            bottom: 6,
            child: Text('🐹', style: TextStyle(fontSize: 32)),
          ),
          // Cart icon di tengah bawah dengan blue circle
          Positioned(
            bottom: 18,
            child: Container(
              height: 62,
              width: 62,
              decoration: BoxDecoration(
                color: _brandBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _brandBlue.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shopping_cart_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
