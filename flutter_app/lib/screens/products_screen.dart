import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../state/recently_viewed_store.dart';
import '../utils/formatters.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_product_image.dart';
import '../widgets/app_ui.dart';
import '../widgets/product_card.dart';
import '../widgets/skeleton_product_card.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_surface.dart';
import '../widgets/barcode_scanner_modal.dart';
import '../widgets/voice_search_modal.dart';

const _brandBlue = NataloColors.nataloBlue;
const _textPrimary = Color(0xFF102033);
const _textSecondary = Color(0xFF64748B);
const _borderSoft = Color(0xFFE5EAF1);
const _dangerRed = Color(0xFFEF4444);

/// Products catalog screen. Accept opsional filter awal dari navigation.
class ProductsScreen extends StatefulWidget {
  final String? selectedBrand;
  final String? initialQuery;
  final String? initialCategory;

  const ProductsScreen({
    super.key,
    this.selectedBrand,
    this.initialQuery,
    this.initialCategory,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = productService.fetchAll(
      brand: widget.selectedBrand,
      category: widget.initialCategory,
      query: widget.initialQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: NataloColors.primary,
        onRefresh: _refreshAll,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _ProductPageHeader(title: title),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  minExtent: 192,
                  maxExtent: 192,
                  child: _CatalogHeader(
                    controller: _searchController,
                    query: _query,
                    visibleCount: products.length,
                    totalCount: _result.total ?? products.length,
                    loading: _loading,
                    activeCategory: _filter.category,
                    activeFilterCount: _filter.activeCount,
                    activeMode: _activeMode,
                    onQueryChanged: _onQueryChanged,
                    onSubmitQuery: _commitSearch,
                    onBarcodeResult: _handleBarcodeResult,
                    onOpenSort: _openSortSheet,
                    onOpenFilters: _openFilterSheet,
                    onFilterModeChanged: _onFilterModeChanged,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SearchSuggestionPanel(
                  query: _query,
                  suggestions: _suggestions,
                  loading: _suggestionLoading,
                  history: _searchHistory,
                  onProduct: (item) => _commitSearch(item.name),
                  onCategory: (item) => _applySuggestedCategory(item.name),
                  onBrand: (item) => _applySuggestedBrand(item.name),
                  onSearchQuery: _commitSearch,
                  onHistoryTap: _commitSearch,
                  onClearHistory: _clearSearchHistory,
                ),
              ),
              if (hasLoadError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ProductErrorState(onRetry: _loadProducts),
                )
              else if (_loading && products.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.52,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const SkeletonProductCard(
                        showAddToCart: true,
                      ),
                      childCount: 8,
                    ),
                  ),
                )
              else if (products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyProductsState(onReset: _resetFilters),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.52,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = products[index];
                        return ProductCard(
                          product: product,
                          onTap: () => _openProduct(product),
                          showAddToCart: true,
                          showWishlistButton: false,
                        );
                      },
                      childCount: products.length,
                    ),
                  ),
                ),
              if (_loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 28),
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: NataloColors.primary,
                        ),
                      ),
                    ),
                  ),
                )
              else if (!_hasMore && products.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 116),
                    child: Center(
                      child: Text(
                        'Sudah sampai akhir katalog',
                        style: TextStyle(
                          color: NataloColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
    );
  }
}

class _ProductPageHeader extends StatelessWidget {
  final String title;

  const _ProductPageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
          const AppCartButton(),
        ],
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final int visibleCount;
  final int totalCount;
  final bool loading;
  final String? activeCategory;
  final int activeFilterCount;
  final _ProductFilterMode activeMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitQuery;
  final ValueChanged<String> onBarcodeResult;
  final VoidCallback onOpenSort;
  final VoidCallback onOpenFilters;
  final ValueChanged<_ProductFilterMode> onFilterModeChanged;

  const _CatalogHeader({
    required this.controller,
    required this.query,
    required this.visibleCount,
    required this.totalCount,
    required this.loading,
    required this.activeCategory,
    required this.activeFilterCount,
    required this.activeMode,
    required this.onQueryChanged,
    required this.onSubmitQuery,
    required this.onBarcodeResult,
    required this.onOpenSort,
    required this.onOpenFilters,
    required this.onFilterModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSearchField(
              controller: controller,
              hintText: 'Cari produk Natalo',
              query: query,
              onChanged: onQueryChanged,
              onClear: () {
                controller.clear();
                onQueryChanged('');
              },
              onSubmitted: onSubmitQuery,
              onVoiceTap: () async {
                // Voice search — buka modal, kembalikan transcript final lalu
                // commit search. Native SpeechRecognizer support partial +
                // bahasa Indonesia (id_ID) jauh lebih akurat dari WebView API.
                final result = await showVoiceSearchModal(context);
                if (result == null || result.isEmpty) return;
                controller.text = result;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: result.length),
                );
                onSubmitQuery(result);
              },
              onBarcodeTap: () async {
                // Barcode scan — native camera + ML Kit barcode detection.
                // Smart lookup: kalau code match product di list → langsung
                // navigate ke detail. Kalau tidak → fallback ke search.
                final code = await showBarcodeScanner(context);
                if (code == null || code.isEmpty) return;
                onBarcodeResult(code);
              },
            ),
            const SizedBox(height: 14),
            _ProductSummary(
              visibleCount: visibleCount,
              totalCount: totalCount,
              loading: loading,
              onOpenSort: onOpenSort,
            ),
            const SizedBox(height: 12),
            _GlassyFilterBar(
              selectedMode: activeMode,
              activeCategory: activeCategory,
              activeFilterCount: activeFilterCount,
              onChanged: onFilterModeChanged,
              onOpenAdvancedFilter: onOpenFilters,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final VoidCallback onReset;

  const _EmptyProductsState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: NataloColors.primaryLight,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: NataloColors.primary,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Produk tidak ditemukan',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coba kata kunci lain atau ubah filter pencarian.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onReset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text(
              'Reset Filter',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ProductErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: _dangerRed,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Gagal memuat produk',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Periksa koneksi internet kamu lalu coba lagi.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text(
              'Coba Lagi',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active filter mode untuk pinned glassy bar (single-select).
enum _ProductFilterMode {
  semua,
  kategori,
  baru,
  populer,
}

extension _ProductFilterModeMeta on _ProductFilterMode {
  String get label {
    switch (this) {
      case _ProductFilterMode.semua:
        return 'Semua';
      case _ProductFilterMode.kategori:
        return 'Kategori';
      case _ProductFilterMode.baru:
        return 'Produk Baru';
      case _ProductFilterMode.populer:
        return 'Populer';
    }
  }

  IconData get icon {
    switch (this) {
      case _ProductFilterMode.semua:
        return Icons.apps_rounded;
      case _ProductFilterMode.kategori:
        return Icons.category_rounded;
      case _ProductFilterMode.baru:
        return Icons.fiber_new_rounded;
      case _ProductFilterMode.populer:
        return Icons.local_fire_department_rounded;
    }
  }
}

/// Summary row: counter "Menampilkan X dari Y" + chip pill aktif filter mode.
class _ProductSummary extends StatelessWidget {
  final int visibleCount;
  final int totalCount;
  final bool loading;
  final VoidCallback onOpenSort;

  const _ProductSummary({
    required this.visibleCount,
    required this.totalCount,
    required this.loading,
    required this.onOpenSort,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            loading
                ? 'Memuat produk...'
                : 'Menampilkan $visibleCount dari $totalCount produk',
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenSort,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _brandBlue.withValues(alpha: 0.14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Urutkan',
                    style: TextStyle(
                      color: _brandBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(width: 5),
                  Icon(
                    Icons.swap_vert_rounded,
                    color: _brandBlue,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pinned glassy filter bar — sticky di top scroll, 4 pills equal width,
/// backdrop blur halus, animated selection. Tombol tune di kanan untuk
/// advanced filter sheet (brand, sort, stock, discount).
class _GlassyFilterBar extends StatelessWidget {
  final _ProductFilterMode selectedMode;
  final String? activeCategory;
  final int activeFilterCount;
  final ValueChanged<_ProductFilterMode> onChanged;
  final VoidCallback onOpenAdvancedFilter;

  const _GlassyFilterBar({
    required this.selectedMode,
    required this.activeCategory,
    required this.activeFilterCount,
    required this.onChanged,
    required this.onOpenAdvancedFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _ProductFilterMode.values.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _ProductFilterMode.values.length) {
            return _AdvancedFilterChip(
              count: activeFilterCount,
              onTap: onOpenAdvancedFilter,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = products[i];
              return Card(
                child: ListTile(
                  leading: AppProductImage(
                    imageUrl: p.imageUrl,
                    width: 56,
                    height: 56,
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    formatRupiah(p.finalPrice),
                    style: const TextStyle(
                      color: NataloColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/product-detail',
                    arguments: p,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
