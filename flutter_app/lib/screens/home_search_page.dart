import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../state/recently_viewed_store.dart';
import '../state/search_history_store.dart';
import '../state/trending_placeholder_controller.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_product_image.dart';

/// Fullscreen search page yang dibuka dari search bar Beranda.
///
/// REPLACE bug-prone `showModalBottomSheet` dengan transparent background
/// + blur. Sekarang halaman benar-benar fullscreen via Navigator.push +
/// MaterialPageRoute.
///
/// Layout (saat input kosong):
/// 1. Sticky search header (back + autofocus input + clear)
/// 2. Section "Terakhir Dilihat" (recentlyViewedStore — horizontal cards)
/// 3. Section "Pencarian Terakhir" (searchHistoryStore — list dengan ✕)
/// 4. Section "Trending Search" (6 item grid 2-col)
///
/// Saat user submit query: navigate ke /products dengan query, save ke
/// searchHistoryStore. Back gesture kembali ke Beranda.
class HomeSearchPage extends StatefulWidget {
  const HomeSearchPage({super.key});

  @override
  State<HomeSearchPage> createState() => _HomeSearchPageState();
}

class _HomeSearchPageState extends State<HomeSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleInputChange);
    _searchFocus.addListener(_handleFocusChange);
    // Pause placeholder rotation saat halaman search aktif — user akan
    // langsung type, jadi placeholder sebaiknya stable (current value).
    // Resume saat halaman close (dispose).
    trendingPlaceholderController.pause();
    // Autofocus search field setelah first frame supaya keyboard muncul
    // sambil halaman selesai animate-in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleInputChange);
    _searchFocus.removeListener(_handleFocusChange);
    _searchController.dispose();
    _searchFocus.dispose();
    // Resume rotation saat halaman search dispose — kembali ke Beranda,
    // placeholder Beranda search bar lanjut rotating.
    trendingPlaceholderController.resume();
    super.dispose();
  }

  void _handleInputChange() {
    final v = _searchController.text;
    if (v != _query) setState(() => _query = v);
  }

  void _handleFocusChange() {
    // Field focus → ensure pause (defensive). Unfocus + empty → resume.
    if (_searchFocus.hasFocus) {
      trendingPlaceholderController.pause();
    } else if (_searchController.text.trim().isEmpty) {
      trendingPlaceholderController.resume();
    }
  }

  void _submitQuery(String raw) {
    final keyword = raw.trim();
    if (keyword.isEmpty) return;
    AppHaptics.tap();
    // Persist ke searchHistoryStore (versioned key — sama yang dipakai
    // home recommendation algorithm).
    searchHistoryStore.push(keyword);
    // Navigate ke products screen dengan initial query — replace bukan
    // push supaya back gesture langsung ke Beranda (bukan kembali ke
    // search page yang sudah tidak relevan).
    Navigator.pushReplacementNamed(
      context,
      '/products',
      arguments: ProductCatalogArgs(initialQuery: keyword),
    );
  }

  void _tapKeyword(String keyword) {
    _searchController.text = keyword;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: keyword.length),
    );
    _submitQuery(keyword);
  }

  void _clearInput() {
    AppHaptics.tap();
    _searchController.clear();
  }

  void _openProductDetail(Product product) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SearchHeader(
              controller: _searchController,
              focusNode: _searchFocus,
              hasText: _query.isNotEmpty,
              onBack: () => Navigator.pop(context),
              onSubmitted: _submitQuery,
              onClear: _clearInput,
            ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEF1F4)),
            Expanded(
              child: _SearchInitialContent(
                onTapKeyword: _tapKeyword,
                onTapProduct: _openProductDetail,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── HEADER ───────────────────

class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onBack;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onBack,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back button — touch target 48px
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onBack,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF17202A),
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Search input pill
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(80),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  // Pakai placeholder current dari trending controller —
                  // saat user tap search bar Beranda, controller di-pause
                  // jadi hint TextField sama dengan placeholder Beranda
                  // saat itu (kontinuitas visual). Tetap static selama
                  // user di halaman ini.
                  hintText: trendingPlaceholderController.currentPlaceholder,
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: Color(0xFF94A3B8),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 42, minHeight: 42),
                  suffixIcon: hasText
                      ? IconButton(
                          onPressed: onClear,
                          tooltip: 'Hapus',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: NataloColors.primary,
                      width: 1.4,
                    ),
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

// ─────────────────── INITIAL CONTENT ───────────────────

class _SearchInitialContent extends StatelessWidget {
  final ValueChanged<String> onTapKeyword;
  final ValueChanged<Product> onTapProduct;

  const _SearchInitialContent({
    required this.onTapKeyword,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom + 24;

    return AnimatedBuilder(
      animation: Listenable.merge([recentlyViewedStore, searchHistoryStore]),
      builder: (context, _) {
        final viewed = recentlyViewedStore.items;
        final history = searchHistoryStore.entries;

        return ListView(
          padding: EdgeInsets.fromLTRB(0, 12, 0, bottomPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (viewed.isNotEmpty)
              _RecentlyViewedSection(
                products: viewed.take(8).toList(),
                onTap: onTapProduct,
                onSeeAll: () => Navigator.pushNamed(context, '/products'),
              ),
            if (history.isNotEmpty)
              _RecentSearchSection(
                entries: history.take(5).toList(),
                onTap: onTapKeyword,
              ),
            const _TrendingSearchSection(),
          ],
        );
      },
    );
  }
}

// ─────────────────── TERAKHIR DILIHAT ───────────────────

class _RecentlyViewedSection extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onTap;
  final VoidCallback onSeeAll;

  const _RecentlyViewedSection({
    required this.products,
    required this.onTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Terakhir Dilihat',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: NataloColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Lihat semua',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemCount: products.length,
            itemBuilder: (context, i) {
              final product = products[i];
              return _ViewedCard(product: product, onTap: () => onTap(product));
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ViewedCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ViewedCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 138,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AppProductImage(
                  imageUrl: product.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatRupiah(product.finalPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NataloColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (product.rating > 0) ...[
                  const Icon(
                    Icons.star_rounded,
                    size: 12,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    product.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (product.soldCount > 0) ...[
                    const SizedBox(width: 4),
                    const Text(
                      '•',
                      style: TextStyle(color: Color(0xFFCBD5E1)),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
                if (product.soldCount > 0)
                  Flexible(
                    child: Text(
                      '${_formatSold(product.soldCount)} terjual',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
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

String _formatSold(int n) {
  if (n >= 1000) {
    final value = n / 1000;
    final text =
        value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '${text.replaceAll('.', ',').replaceAll(',0', '')}rb+';
  }
  if (n >= 100) return '${(n ~/ 50) * 50}+';
  return n.toString();
}

// ─────────────────── PENCARIAN TERAKHIR ───────────────────

class _RecentSearchSection extends StatelessWidget {
  final List<String> entries;
  final ValueChanged<String> onTap;

  const _RecentSearchSection({required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Pencarian Terakhir',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (entries.length >= 2)
                TextButton(
                  onPressed: () async {
                    AppHaptics.tap();
                    await searchHistoryStore.clear();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Hapus semua',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final entry in entries)
          _RecentSearchRow(
            entry: entry,
            onTap: () => onTap(entry),
            onDelete: () async {
              AppHaptics.tap();
              await searchHistoryStore.remove(entry);
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _RecentSearchRow extends StatelessWidget {
  final String entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RecentSearchRow({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── TRENDING SEARCH ───────────────────

class _TrendingSearchSection extends StatelessWidget {
  const _TrendingSearchSection();

  // Fallback static — backend trending analytics belum tersedia. Spec
  // section 7 mention prioritas: backend → product search count →
  // popular → fallback manual. Hardcoded list di sini = step terakhir
  // fallback chain, sampai backend trending API ready.
  static const _trendingFallback = [
    'Royal Canin',
    'Pasir Kucing',
    'Whiskas',
    'Kalung Kucing',
    'Makanan Ikan',
    'Vitamin Anjing',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Trending Search',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _trendingFallback.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 10,
              childAspectRatio: 4.2,
            ),
            itemBuilder: (context, i) {
              final keyword = _trendingFallback[i];
              return _TrendingChip(
                keyword: keyword,
                onTap: () {
                  // Parent state wires this via inherited callback —
                  // ambil dari closest _HomeSearchPageState ancestor.
                  final state =
                      context.findAncestorStateOfType<_HomeSearchPageState>();
                  state?._tapKeyword(keyword);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrendingChip extends StatelessWidget {
  final String keyword;
  final VoidCallback onTap;

  const _TrendingChip({required this.keyword, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                size: 16,
                color: NataloColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
