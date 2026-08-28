import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/product.dart';
import '../services/cart_service.dart';
import '../services/member_service.dart';
import '../services/product_service.dart';
import '../state/cart_store.dart';
import '../state/member_store.dart';
import '../state/recently_viewed_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../utils/chrome_autohide.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/animated_counter.dart';
import '../widgets/app_chat_button.dart';
import '../widgets/cart_checkout_pill.dart';
import '../widgets/cart_scroll_view.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_product_image.dart';
import '../widgets/glass_surface.dart';
import '../widgets/compact_commerce_product_card.dart';
import '../widgets/skeleton_product_card.dart';
import '../widgets/product_variant_picker_sheet.dart';

const _brandBlue = NataloColors.nataloBlue;
const _discountRed = Color(0xFFE53958);
const _discountRedSoft = Color(0xFFFFF1F4);
const _discountRedBorder = Color(0xFFFFB8C8);
const _shippingGreen = Color(0xFF12A66A);
// Loyalty (reward poin) — purple star, match checkout styling supaya
// icon consistent antar layar. Sebelumnya cart pakai red ticket untuk
// loyalty voucher juga → confusing user (di checkout muncul beda warna).
const _loyaltyPurple = Color(0xFF7C3AED);
const _loyaltyPurpleSoft = Color(0xFFF3E8FF);
const _loyaltyPurpleBorder = Color(0xFFD9C4F5);
const _shippingGreenSoft = Color(0xFFECFDF3);
const _shippingGreenBorder = Color(0xFFA6F4C5);
// Aksen brand-exclusive: amber gelap (kontras di atas bg soft) — konsisten dgn
// badge grid & chip detail "Brand Eksklusif". Satu sumber di NataloColors.
const _brandExclusiveAmber = NataloColors.brandExclusiveDark;
const _brandExclusiveAmberSoft = NataloColors.brandExclusiveSoft;
const _brandExclusiveAmberBorder = NataloColors.brandExclusiveBorder;
const _voucherBarHeight = 50.0;
const _selectionRowHeight = 42.0;
// Auto-hide chrome collapse — smooth (easeInOut) & sengaja tidak terlalu cepat.
const _chromeAnimDuration = Duration(milliseconds: 340);
// Jeda setelah konten benar-benar BERHENTI sebelum chrome/pil mengembang lagi
// (debounce reveal). Bukan durasi animasi — ini "diam berapa lama dulu". Cukup
// > 1 frame (~16ms) supaya update ballistic beruntun tetap me-reset & tak
// mengembang mid-fling. 300ms terasa responsif tanpa mengembang prematur.
const _chromeRevealDelay = Duration(milliseconds: 300);
const _cartBossOpenCountKey = 'natalo_cart_boss_open_count_v1';
const _cartBossWindowCount = 6;

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen>
    with SingleTickerProviderStateMixin {
  // Center-sliver (CartScrollView) meng-anchor rekomendasi secara struktural,
  // jadi cukup ScrollController biasa. initialScrollOffset sangat negatif →
  // frame pertama ter-clamp ke minScrollExtent (= cart paling atas) tanpa
  // kedip ke rekomendasi.
  final ScrollController _scrollController =
      ScrollController(initialScrollOffset: -100000);
  // Auto-hide chrome (baris "N terpilih" + voucher bar): collapse height→0 saat
  // scroll ke bawah, muncul lagi saat scroll ke atas / berhenti. Aman di
  // center-sliver (perubahan tinggi viewport tak menggeser konten). Animasi
  // smooth (easeInOut, 340ms), collapse penuh → TANPA pita putih.
  late final AnimationController _chromeController;
  late final Animation<double> _chromeAnim;
  // Slide untuk overlay baris atas: shown = Offset.zero, hidden = geser ke atas.
  late final Animation<Offset> _chromeSlideAnim;
  // Pil checkout = kebalikan chrome: muncul saat chrome terlipat. Satu
  // controller yang sama → morph serempak satu napas, tanpa animasi liar.
  late final Animation<double> _pillAnim;
  late final Animation<Offset> _pillSlideAnim;
  Timer? _chromeIdleTimer;
  bool _chromeVisible = true;
  // Jari sedang menyentuh layar? Reveal chrome digate ini: mengembang HANYA
  // saat konten berhenti DAN jari lepas — jadi fling (jari lepas tapi konten
  // masih meluncur) tak memicu mengembang di tengah luncuran.
  bool _pointerDown = false;
  List<Product> _recentlyViewed = const [];
  List<Product> _bossProducts = const [];
  bool _loadingRecentlyViewed = false;
  bool _loadingBossProducts = false;
  bool _loadingMoreBossProducts = false;
  bool _bossProductsHasMore = true;
  String? _bossProductsCursor;
  // Entrance kartu item (fade+translate) dimainkan HANYA saat layar pertama
  // menampilkan item. Setelah itu, kartu yang disisipkan (add dari
  // rekomendasi / beli lagi) muncul TANPA motion supaya tidak ada animasi
  // 220ms di tepi grid saat add — itu ikut terbaca sebagai "glitch".
  bool _didInitialCardAnimation = false;
  List<MemberVoucher> _availableDiscountVouchers = const [];
  List<MemberVoucher> _unavailableDiscountVouchers = const [];
  // _appliedDiscountVoucher = slot product discount (PRODUCT_DISCOUNT only).
  // Sebelumnya juga carry loyalty voucher (via _bestDiscountVoucher yang
  // pick highest dari mixed list), tapi rule Natalo: 1 voucher per type
  // applied bersamaan (1 product + 1 loyalty + 1 shipping). Sekarang
  // dipisah jadi 2 slot supaya match behavior checkout.
  MemberVoucher? _appliedDiscountVoucher;
  MemberVoucher? _appliedLoyaltyVoucher;
  MemberVoucher? _appliedShippingVoucher;
  bool _isManualVoucherSelected = false;
  String? _manualVoucherCode;
  int _lastVoucherSubtotal = -1;
  bool _loadingVouchers = false;
  // Multi-select state lokal — track key item yang user pilih untuk checkout.
  // Default semua item ter-select saat first load (backward compatible). User
  // bisa toggle individual atau select all/none. Tidak persist disk — reset
  // saat keluar screen.
  Set<String> _selectedIds = <String>{};

  /// Isu stok per item (key `productId:variantId`) dari POST /api/cart/validate.
  /// Kosong = semua aman. Dipakai render badge + auto-deselect.
  Map<String, CartValidationIssue> _stockIssues = {};

  @override
  void initState() {
    super.initState();
    _chromeController = AnimationController(
      vsync: this,
      duration: _chromeAnimDuration,
      value: 1,
    );
    _chromeAnim = CurvedAnimation(
      parent: _chromeController,
      curve: Curves.easeInOutCubic,
    );
    _chromeSlideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(_chromeAnim);
    _pillAnim = ReverseAnimation(_chromeAnim);
    // Slide halus dari bawah TANPA overshoot (easeInOutCubic dari parent).
    _pillSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(_pillAnim);
    _loadRecentlyViewed();
    _loadBossProducts();
    _scrollController.addListener(_onCartScroll);
    // Default select semua cart items yang ada saat first build.
    _selectedIds = cartStore.items.map((i) => i.key).toSet();
    cartStore.addListener(_onCartChanged);
    memberStore.addListener(_onMemberChanged);
    recentlyViewedStore.addListener(_loadRecentlyViewed);
    _syncVouchersForSelection();
    // Validasi stok server saat cart dibuka — badge stok habis/sisa-N +
    // auto-deselect item habis supaya tidak ikut checkout.
    _validateStock();
  }

  String _issueKeyForItem(CartItem item) =>
      '${item.product.id}:${item.variantId ?? ''}';

  CartValidationIssue? _issueFor(CartItem item) =>
      _stockIssues[_issueKeyForItem(item)];

  /// Panggil endpoint validasi stok, map issue → item, lalu auto-deselect
  /// item yang stoknya habis (action "removed"). Best-effort: kalau error,
  /// _stockIssues dikosongkan (anggap aman, checkout server tetap guard).
  Future<void> _validateStock() async {
    final items = cartStore.items;
    if (items.isEmpty) {
      if (mounted) setState(() => _stockIssues = {});
      return;
    }
    final result = await cartService.validate(items);
    if (!mounted) return;
    final map = <String, CartValidationIssue>{};
    for (final issue in result.issues) {
      map[issue.matchKey] = issue;
    }
    // JANGAN tambah re-anchor/koreksi scroll di sini. Dulu (v1.0.167) validasi
    // ini mengoreksi offset untuk reflow badge stok & itu REGRESI: balas ~300ms
    // setelah add, bertabrakan dgn pagination → "loncat" tertunda + gap kosong.
    // Sejak center-sliver (v1.0.171, lihat widgets/cart_scroll_view.dart), kartu
    // yang disisipkan ada di sisi NEGATIF sliver → rekomendasi tak bergeser
    // secara struktural. Reflow badge stok aman tanpa koreksi scroll apa pun.
    setState(() {
      _stockIssues = map;
      // Auto-deselect item out-of-stock supaya keluar dari subtotal +
      // tombol checkout.
      for (final item in items) {
        final issue = map[_issueKeyForItem(item)];
        if (issue != null && issue.isOutOfStock) {
          _selectedIds.remove(item.key);
        }
      }
    });
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
    _scrollController.removeListener(_onCartScroll);
    _scrollController.dispose();
    _chromeIdleTimer?.cancel();
    _chromeController.dispose();
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

    // Katalog: majukan window 8 item tiap buka, siklis (bungkus balik ke 0
    // setelah _cartBossWindowCount putaran) supaya ekor berputar tanpa offset
    // tumbuh tak terbatas. Seed di bawah merotasi bagian personalisasi (top).
    final rotation = (openCount - 1) % _cartBossWindowCount;
    final startOffset = rotation * 8;
    final startCursor = startOffset > 0 ? '$startOffset' : null;
    final bossSeed = 'boss-$openCount';
    // Layer 1 + Layer 2 paralel — personalized (purchase × view signal) +
    // rotation catalog browse. Tidak ada dependency antara keduanya, jadi
    // bisa di-fire bersamaan. Hemat ~300ms vs sequential await.
    final cartProductIds =
        cartStore.items.map((item) => item.product.id).toList();
    final viewedIds = recentlyViewedStore.items.map((p) => p.id).toList();

    // BUGFIX(audit): tanpa try/catch, kalau fetch throw (API/DB down),
    // setState(_loadingBossProducts=false) tidak pernah tercapai → skeleton
    // rekomendasi "Ayoo diborong" loading SELAMANYA. Catch reset flag +
    // biarkan section kosong (graceful degrade), bukan stuck.
    try {
      final results = await Future.wait<dynamic>([
        productService.fetchPersonalizedRecommendations(
          viewedIds: viewedIds,
          excludeIds: cartProductIds,
          limit: 8,
          seed: bossSeed,
        ),
        productService.fetchProductsPage(
          cursor: startCursor,
          limit: 8,
          inStock: true,
          hasPrice: true,
          withImage: false,
        ),
      ]);
      final personalized = results[0] as List<Product>;
      var page = results[1] as ProductPage;

      // Fallback rotation kalau startOffset out-of-bounds — ulangi tanpa cursor.
      if (page.products.isEmpty && startCursor != null) {
        page = await productService.fetchProductsPage(
          limit: 8,
          inStock: true,
          hasPrice: true,
          withImage: false,
        );
      }
      if (!mounted) return;

      // Merge personalized + rotation, dedup by id, exclude cart products.
      final cartIdSet = cartProductIds.toSet();
      final seen = <String>{};
      final merged = <Product>[];
      for (final product in [...personalized, ...page.products]) {
        if (product.id.isEmpty) continue;
        if (cartIdSet.contains(product.id)) continue;
        if (!seen.add(product.id)) continue;
        merged.add(product);
      }

      setState(() {
        _bossProducts = merged;
        _bossProductsCursor = page.nextCursor;
        _bossProductsHasMore = page.hasMore;
        _loadingBossProducts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBossProducts = false);
    }
  }

  void _onCartScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;

    // Center-sliver: cart ada di sisi NEGATIF, rekomendasi di sisi positif.
    // Kalau rekomendasi pendek, maxScrollExtent bisa <= 0 & pixels(negatif)
    // >= max-520 → cegah load-more storm.
    if (position.maxScrollExtent <= 0) return;

    if (_loadingBossProducts ||
        _loadingMoreBossProducts ||
        !_bossProductsHasMore) {
      return;
    }

    if (position.pixels >= position.maxScrollExtent - 520) {
      _loadMoreBossProducts();
    }
  }

  // ── Auto-hide chrome (drag-driven, condense-pill) ──
  bool _onChromeScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      // Keputusan HIDE/SHOW hanya dari drag USER (dragDetails != null) — jumpTo
      // anchor awal & scroll programatik lain tak boleh salah-sembunyikan.
      if (notification.dragDetails != null) {
        final metrics = notification.metrics;
        final action = chromeActionForScroll(
          scrollDelta: notification.scrollDelta ?? 0,
          pixels: metrics.pixels,
          minExtent: metrics.minScrollExtent,
          maxExtent: metrics.maxScrollExtent,
          currentlyVisible: _chromeVisible,
        );
        if (action == ChromeAction.hide) _setChromeVisible(false);
        if (action == ChromeAction.show) _setChromeVisible(true);
      }
      // Debounce reveal ke "konten BERHENTI": tiap update scroll (drag MAUPUN
      // ballistic/fling) me-reset timer. Selama konten masih meluncur, update
      // terus masuk → timer tak pernah fire di tengah luncuran. Baru setelah
      // konten benar-benar diam → 400ms → mengembang. Callback tetap digate
      // !_pointerDown (lihat _armIdleReveal) → tetap patuh aturan "jari lepas".
      _armIdleReveal();
    }
    return false;
  }

  void _setChromeVisible(bool visible) {
    if (_chromeVisible == visible) return;
    _chromeVisible = visible;
    if (visible) {
      _chromeController.forward();
    } else {
      _chromeController.reverse();
    }
  }

  // Setelah scroll benar-benar berhenti (tak ada update lagi) selama 400ms,
  // chrome muncul lagi — TAPI hanya kalau jari sudah lepas (!_pointerDown).
  // Dicek saat timer fire (bukan saat event) → bebas dari masalah urutan
  // event (mis. tangkap-fling), sekaligus jaga "jari di layar = diam".
  void _armIdleReveal() {
    _chromeIdleTimer?.cancel();
    _chromeIdleTimer = Timer(_chromeRevealDelay, () {
      if (mounted && !_pointerDown) _setChromeVisible(true);
    });
  }

  Future<void> _loadMoreBossProducts() async {
    if (_loadingMoreBossProducts || !_bossProductsHasMore) return;
    setState(() => _loadingMoreBossProducts = true);
    // BUGFIX(audit): tanpa try/catch, throw saat fetch bikin
    // _loadingMoreBossProducts stuck true → guard di _onCartScroll selalu
    // return → pagination mati PERMANEN sisa sesi. Catch reset flag.
    try {
      final page = await productService.fetchProductsPage(
        cursor: _bossProductsCursor,
        limit: 8,
        inStock: true,
        hasPrice: true,
        withImage: false,
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
    } catch (_) {
      if (mounted) setState(() => _loadingMoreBossProducts = false);
    }
  }

  void _onCartChanged() {
    // Auto-add baru added cart items ke selection (default semua selected).
    // Prune selected IDs yang sudah tidak di cart (saat item di-remove).
    final cartKeys = cartStore.items.map((i) => i.key).toSet();
    final hasNewItem = cartKeys.any((key) => !_selectedIds.contains(key));
    // Anti-loncat sekarang STRUKTURAL: item baru mendarat di sliver SEBELUM
    // center (CartScrollView) → rekomendasi yang dilihat tak bergeser. Tak
    // perlu arm/koreksi pixel lagi.
    setState(() {
      // Add semua key yang belum di set (new items).
      for (final key in cartKeys) {
        _selectedIds.add(key);
      }
      // Prune key yang sudah tidak di cart.
      _selectedIds.retainAll(cartKeys);
      // Bersihkan issue untuk item yang sudah tidak ada di cart.
      _stockIssues.removeWhere((key, _) => !cartStore.items.any(
            (item) => _issueKeyForItem(item) == key,
          ));
    });
    _syncVouchersForSelection();
    // Re-validasi stok kalau ada item baru masuk cart (mis. dari "Beli
    // lagi" / rekomendasi) supaya badge stok langsung akurat.
    if (hasNewItem) _validateStock();
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

  double get _voucherDiscount {
    if (_selectedItems.isEmpty) return 0;
    // Sum product + loyalty discount, capped at subtotal supaya tidak
    // negative. Per business rule: 1 product + 1 loyalty bisa apply
    // bersamaan, total tidak boleh exceed selected subtotal.
    final productDiscount = _appliedDiscountVoucher?.discount.toDouble() ?? 0;
    final loyaltyDiscount = _appliedLoyaltyVoucher?.discount.toDouble() ?? 0;
    final total = productDiscount + loyaltyDiscount;
    final cap = _selectedSubtotal;
    return total > cap ? cap : total;
  }

  double get _shippingDiscount {
    final voucher = _appliedShippingVoucher;
    if (_selectedItems.isEmpty || voucher == null) return 0;
    return voucher.discount.toDouble();
  }

  // Cart cuma tampilkan saving dari voucher produk/loyalty (yang apply ke
  // subtotal). Saving gratis-ongkir TIDAK ditampilkan di cart karena
  // ongkir sendiri tidak ditampilkan di cart (baru dihitung di checkout
  // setelah pilih alamat + kurir). Gratis-ongkir saving muncul di checkout.
  double get _totalVoucherSaving => _voucherDiscount;

  /// Detect apakah voucher ini termasuk kategori shipping (gratis ongkir).
  /// Cek 2 indicator dari backend response:
  ///   1. `isFreeShipping` getter (type == 'PUBLIC_FREE_SHIPPING')
  ///   2. `isShippingDiscount` getter (discountScope == 'SHIPPING')
  /// Fallback: cocokkan teks kode/judul/deskripsi voucher terhadap
  /// 'ongkir', 'gratis kirim', atau 'free shipping'.
  /// Method ini dipakai untuk pisahkan slot shipping voucher vs discount
  /// voucher di dual-slot voucher UI (1 customer + 1 shipping).
  bool _isCartShippingVoucher(MemberVoucher voucher) {
    return _isCartShippingVoucherData(voucher);
  }

  // Cart bar tampilkan SUBTOTAL produk (setelah diskon voucher produk/
  // loyalty), BUKAN total bayar final. Ongkir TIDAK dimasukkan di sini
  // karena belum diketahui (baru dihitung di checkout setelah user pilih
  // alamat + kurir). Sebelumnya cart pakai ongkir hardcode Rp15.000 yang
  // bikin angka cart hampir selalu beda dengan total asli di checkout →
  // user bingung. Sekarang cart = subtotal akurat, checkout = total
  // lengkap (subtotal + ongkir asli - semua diskon). Pola Shopee/Tokped.
  double get _grandTotal {
    final total = _selectedSubtotal - _voucherDiscount;
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
        _appliedLoyaltyVoucher = null;
        _appliedShippingVoucher = null;
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
        final productIds =
            _selectedItems.map((item) => item.productId).toSet().toList();
        final result =
            await memberService.fetchCartVouchers(subtotal, productIds);
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

    // Per business rule Natalo: 3 voucher type bisa apply bersamaan
    // (1 ongkir + 1 produk + 1 reward poin). Pick best per type separately.
    final bestProduct = _bestProductVoucher(available);
    final bestLoyalty = _bestLoyaltyVoucher(available);
    final bestShipping = _bestShippingVoucher(available);
    var nextProduct = _appliedDiscountVoucher;
    var nextLoyalty = _appliedLoyaltyVoucher;
    var nextShipping = bestShipping;
    var manualStillEligible = false;

    if (_isManualVoucherSelected && _manualVoucherCode != null) {
      final manualVoucher = _findVoucherByCode(available, _manualVoucherCode!);
      if (manualVoucher != null && _isCartShippingVoucher(manualVoucher)) {
        manualStillEligible = true;
        // Manual pick shipping (termasuk brand-exclusive) tetap dihormati.
        nextShipping = manualVoucher;
        nextProduct = bestProduct;
        nextLoyalty = bestLoyalty;
      } else if (manualVoucher != null) {
        manualStillEligible = true;
        // Manual override pick — replace slot yang sesuai type.
        if (manualVoucher.isLoyaltyClaim) {
          nextLoyalty = manualVoucher;
          nextProduct = bestProduct;
        } else {
          nextProduct = manualVoucher;
          nextLoyalty = bestLoyalty;
        }
        nextShipping = bestShipping;
      }
    }

    if (!_isManualVoucherSelected || !manualStillEligible) {
      nextProduct = bestProduct;
      nextLoyalty = bestLoyalty;
      nextShipping = bestShipping;
    }

    if (!mounted) return;
    setState(() {
      _appliedDiscountVoucher = nextProduct;
      _appliedLoyaltyVoucher = nextLoyalty;
      _appliedShippingVoucher = nextShipping;
      if (_isManualVoucherSelected && !manualStillEligible) {
        _isManualVoucherSelected = false;
        _manualVoucherCode = null;
      }
    });
  }

  /// Best PRODUCT_DISCOUNT voucher dari list. Exclude shipping + loyalty.
  MemberVoucher? _bestProductVoucher(List<MemberVoucher> vouchers) {
    final eligible = vouchers
        .where(
          (voucher) =>
              voucher.discount > 0 &&
              !_isCartShippingVoucher(voucher) &&
              !voucher.isLoyaltyClaim,
        )
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) => b.discount.compareTo(a.discount));
    return eligible.first;
  }

  /// Best LOYALTY_CLAIM voucher dari list. Loyalty type only.
  MemberVoucher? _bestLoyaltyVoucher(List<MemberVoucher> vouchers) {
    final eligible = vouchers
        .where(
          (voucher) => voucher.discount > 0 && voucher.isLoyaltyClaim,
        )
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) => b.discount.compareTo(a.discount));
    return eligible.first;
  }

  /// Best real gratis-ongkir voucher untuk cart. Brand-exclusive ongkir
  /// TIDAK auto-apply (user pilih manual) -- konsisten dgn checkout
  /// _ensureAutoApplyFallback. Tidak filter discount>0 karena voucher
  /// gratis-ongkir bisa discount=0 di konteks cart (dihitung di checkout).
  MemberVoucher? _bestShippingVoucher(List<MemberVoucher> vouchers) {
    final eligible = vouchers
        .where((voucher) =>
            _isCartShippingVoucher(voucher) && !voucher.isBrandExclusive)
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
    if (!memberStore.isLoggedIn) {
      AppToast.showBanner(
        context,
        'Masuk member dulu untuk lanjut checkout.',
        kind: ToastKind.info,
      );
      Navigator.pushNamed(
        context,
        '/member/login',
        arguments: {'redirect': '/checkout'},
      );
      return;
    }
    // CRITICAL: pass HANYA item yang dipilih (_selectedItems) ke checkout.
    // Tanpa argument ini, route fallback ke `const CheckoutScreen()` yang
    // pakai SEMUA cartStore.items — bug: user uncheck 2 dari 5 item, cart
    // bar tampilkan total 3 item, tapi order ke-create 5 item. Seluruh
    // fitur multi-select jadi bohong soal apa yang di-order.
    Navigator.pushNamed(
      context,
      '/checkout',
      arguments: _selectedItems,
    );
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
        selectedDiscountCode: _appliedDiscountVoucher?.code,
        selectedLoyaltyCode: _appliedLoyaltyVoucher?.code,
        selectedShippingCode: _appliedShippingVoucher?.code,
        shippingSelected: _appliedShippingVoucher != null,
        isManual: _isManualVoucherSelected,
        loading: _loadingVouchers,
      ),
    );
    if (picked == null) return;

    AppHaptics.success();
    final isRemove = picked.remove;
    setState(() {
      if (isRemove) {
        _appliedDiscountVoucher = null;
        _appliedLoyaltyVoucher = null;
        _appliedShippingVoucher = null;
        _isManualVoucherSelected = false;
        _manualVoucherCode = null;
        return;
      }

      _isManualVoucherSelected = true;
      // Manual override code untuk validation tracking — pakai code dari
      // slot pertama yang ke-set (priority: product > loyalty > shipping).
      _manualVoucherCode = picked.discountVoucher?.code ??
          picked.loyaltyVoucher?.code ??
          picked.shippingCode;
      _appliedDiscountVoucher = picked.discountVoucher;
      _appliedLoyaltyVoucher = picked.loyaltyVoucher;
      _appliedShippingVoucher = picked.shippingSelected &&
              picked.shippingCode != null
          ? _findVoucherByCode(_availableDiscountVouchers, picked.shippingCode!)
          : null;
    });
    // Setelah Hapus Voucher, re-run auto-apply supaya 3 slot ke-isi
    // ulang dari best available (ongkir + diskon produk + reward poin).
    // Tanpa ini, user harus toggle item cart dulu untuk trigger sync.
    if (isRemove) {
      _syncVouchersForSelection();
    }
  }

  // _syncCart dihapus — cloud sync icon di-remove dari AppBar (per
  // simplified design). Cart auto-sync sudah via login flow.

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      // Solid surface bg — override theme transparency yang bikin header
      // & content nampak semi-transparent / kurang sharp (spec: header
      // harus solid, tidak terkena efek glass/blur dari layer lain).
      // Latar seluruh halaman Keranjang abu (a la Shopee) — kartu item &
      // grid rekomendasi putih menonjol di atas abu. AppBar tetap solid putih.
      backgroundColor: commerceGridSurfaceTint(context),
      // Custom title dengan count subtitle — match PWA cart header
      // "Keranjang\n0 jenis produk (0 item)".
      // AppBar override eksplisit ke putih solid (theme global pakai
      // surface 0.90 = semi-transparent yang inherit ke cart → header
      // jadi kurang tajam). Border bawah tipis untuk crisp visual edge.
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFE5EAF2),
            width: 1,
          ),
        ),
        title: const Text('Keranjang'),
        actions: [
          // Wishlist heart icon — replace dari trash/kosongkan action lama.
          // Trash icon sekarang muncul di selection row di bawah header,
          // bukan di AppBar. Pattern match Tokopedia / e-commerce modern.
          IconButton(
            tooltip: 'Wishlist',
            // Warna onSurface (default M3 IconButton = abu onSurfaceVariant) +
            // chrome rapat samakan dgn AppChatButton → ikon header hitam &
            // jaraknya konsisten.
            color: cs.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 44),
            // shrinkWrap: tanpa ini MaterialTapTargetSize.padded tetap
            // melebarkan layout ke 48px → gap antar ikon header jauh.
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            onPressed: () => Navigator.pushNamed(context, '/wishlist'),
            icon: const Icon(Icons.favorite_border_rounded),
          ),
          const AppChatButton(),
          // Jarak tepi kanan — ikon shrinkWrap (34px) cuma nyisa 4px dari
          // tepi layar → tampak condong kanan vs header Beranda (margin 16).
          const SizedBox(width: 12),
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

          // Entrance kartu hanya pada mount pertama. Insert berikutnya →
          // animateCards=false → kartu baru muncul instan tanpa motion di
          // tepi grid (lihat _didInitialCardAnimation).
          if (!_didInitialCardAnimation) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _didInitialCardAnimation = true;
            });
          }
          final animateCards = !_didInitialCardAnimation;

          final showVoucherArea = memberStore.isLoggedIn;

          final dividerColor = Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.outlineVariant
              : const Color(0xFFEEF2F6);
          final hasOutOfStock =
              _stockIssues.values.any((issue) => issue.isOutOfStock);

          // CENTER-SLIVER (CartScrollView): blok cart-items di sliver SEBELUM
          // center, rekomendasi DI center → menyisipkan item cart TIDAK
          // menggeser rekomendasi yang sedang dilihat. Bebas loncat by-design
          // (geometri native, bukan aritmetika maxScrollExtent yang rapuh thd
          // estimasi lazy — biang gagal v165–v170). Baris "N terpilih" +
          // voucher bar = sibling persisten (Tahap 2: collapsing auto-hide).
          return Listener(
            // Lacak status jari untuk gate reveal. onPointerDown menandai jari
            // nempel + batalkan reveal tertunda (sentuh lagi tak memicu
            // mengembang). onPointerUp/Cancel menandai jari lepas + arm reveal.
            // Reveal aktual (di _armIdleReveal) baru jalan kalau konten sudah
            // berhenti (debounce di _onChromeScroll) DAN jari lepas → fling yang
            // masih meluncur tak mengembang, & jari nempel-diam juga tak.
            onPointerDown: (_) {
              _pointerDown = true;
              _chromeIdleTimer?.cancel();
            },
            onPointerUp: (_) {
              _pointerDown = false;
              _armIdleReveal();
            },
            onPointerCancel: (_) {
              _pointerDown = false;
              _armIdleReveal();
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _onChromeScroll,
              child: Column(
                children: [
                  // Baris "N terpilih" = OVERLAY (Positioned di Stack), BUKAN
                  // sibling Column. Sebagai sibling, muncul-lagi merebut 42px &
                  // mendorong isi turun; sebagai overlay dia slide+fade di ATAS
                  // konten → area scroll tak berubah ukuran → NOL dorongan.
                  // Daftar diberi padding atas supaya kartu pertama tak ketutup.
                  Expanded(
                    child: Stack(
                      children: [
                        CartScrollView(
                          controller: _scrollController,
                          leadingSlivers: [
                            const SliverToBoxAdapter(
                              child: SizedBox(height: _selectionRowHeight + 12),
                            ),
                            if (hasOutOfStock)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: _CartStockBanner(
                                    count: _stockIssues.values
                                        .where((issue) => issue.isOutOfStock)
                                        .length,
                                  ),
                                ),
                              ),
                          ],
                          itemIds: [for (final item in items) item.key],
                          itemBuilder: (context, dataIndex) {
                            final item = items[dataIndex];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Divider di ATAS tiap kartu kecuali paling atas
                                  // (dataIndex 0) → garis antar kartu, indent 42.
                                  if (dataIndex > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 42),
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: dividerColor,
                                      ),
                                    ),
                                  _CartItemCard(
                                    item: item,
                                    index: dataIndex,
                                    selected: _selectedIds.contains(item.key),
                                    onToggleSelected: () =>
                                        _toggleItem(item.key),
                                    stockIssue: _issueFor(item),
                                    animateEntrance: animateCards,
                                  ),
                                ],
                              ),
                            );
                          },
                          center: Padding(
                            // Horizontal 0 supaya latar abu grid rekomendasi
                            // (di dalam section) bisa full-bleed ke tepi layar.
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _CartRecommendationsSection(
                                  key: const ValueKey('cart-rec-recently'),
                                  title: 'Yuk dilihat lagi',
                                  products: _recentlyViewed,
                                  loading: _loadingRecentlyViewed,
                                  showLoadingPlaceholder: false,
                                ),
                                const SizedBox(height: 18),
                                _CartRecommendationsSection(
                                  key: const ValueKey('cart-rec-boss'),
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
                        // Overlay baris "N terpilih" — melayang, slide+fade
                        // (bukan collapse) → tak mendorong konten saat muncul.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SlideTransition(
                            position: _chromeSlideAnim,
                            child: FadeTransition(
                              opacity: _chromeAnim,
                              // Gate pointer ikut animasi (bukan _chromeVisible yg
                              // tak memicu rebuild) → saat chrome nyaris hilang,
                              // baris non-interaktif; saat tampil, tombol hapus
                              // langsung responsif.
                              child: AnimatedBuilder(
                                animation: _chromeController,
                                builder: (context, child) => IgnorePointer(
                                  ignoring: _chromeController.value < 0.5,
                                  child: child,
                                ),
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
                        // Pil checkout melayang — muncul saat chrome terlipat
                        // (ReverseAnimation). CTA + total + hemat tidak pernah
                        // hilang dari layar. Tap seluruh pil = checkout.
                        if (_selectedItems.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            // Offset aman dari home-indicator saat bar terlipat
                            // (area scroll memanjang ke dasar layar).
                            bottom: 12 + MediaQuery.paddingOf(context).bottom,
                            // Gate pointer ikut animasi: pil interaktif hanya saat
                            // chrome (nyaris) terlipat. _chromeVisible tak memicu
                            // rebuild → tanpa ini tap pil tembus ke grid di
                            // belakang / pil pudar malah menelan tap.
                            child: AnimatedBuilder(
                              animation: _chromeController,
                              builder: (context, child) => IgnorePointer(
                                ignoring: _chromeController.value > 0.5,
                                child: child,
                              ),
                              child: SlideTransition(
                                position: _pillSlideAnim,
                                child: FadeTransition(
                                  opacity: _pillAnim,
                                  child: Center(
                                    child: CartCheckoutPill(
                                      quantity: _selectedQuantity,
                                      totalText: formatRupiah(_grandTotal),
                                      savingText: _totalVoucherSaving > 0
                                          ? 'Hemat ${formatRupiah(_totalVoucherSaving)}'
                                          : null,
                                      voucherActive:
                                          _appliedDiscountVoucher != null ||
                                              _appliedLoyaltyVoucher != null ||
                                              _appliedShippingVoucher != null,
                                      onTap: _goToCheckout,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Voucher bar — collapse (height→0) ke arah checkout saat scroll.
                  if (showVoucherArea)
                    SizeTransition(
                      sizeFactor: _chromeAnim,
                      // Dulu `axisAlignment: 1` (usang sejak v3.41). Pemetaan
                      // resmi dari dokumentasi SizeTransition: untuk
                      // Axis.vertical (default), `axisAlignment: x` menjadi
                      // AlignmentDirectional(-1.0, x) — di sini (-1, 1),
                      // yaitu bottomStart. Bukan sekadar ganti nama: tipenya
                      // berubah dari double ke Alignment.
                      alignment: AlignmentDirectional.bottomStart,
                      child: _StickyVoucherBar(
                        hasSelection: _selectedItems.isNotEmpty,
                        loading: _loadingVouchers,
                        discountVoucher: _appliedDiscountVoucher,
                        discountAmount: _voucherDiscount,
                        shippingSelected: _appliedShippingVoucher != null,
                        shippingDiscount: _shippingDiscount,
                        shippingText: _appliedShippingVoucher != null
                            ? _shippingVoucherDisplayTitle(
                                _appliedShippingVoucher!)
                            : 'Gratis Ongkir',
                        onTap: _selectedItems.isEmpty
                            ? null
                            : () {
                                AppHaptics.tap();
                                _openVoucherSheet();
                              },
                      ),
                    ),
                  // Summary bar ikut melipat bersama voucher bar — CTA checkout
                  // pindah ke pil melayang selama scroll (pola condense).
                  SizeTransition(
                    sizeFactor: _chromeAnim,
                    // Lihat catatan pemetaan di SizeTransition voucher bar
                    // di atas — sumbu vertikal, axisAlignment 1 -> (-1, 1).
                    alignment: AlignmentDirectional.bottomStart,
                    child: _CartSummaryBar(
                      grandTotal: _grandTotal,
                      totalSaving: _totalVoucherSaving,
                      selectedQuantity: _selectedQuantity,
                      disabled: _selectedItems.isEmpty,
                      onCheckout: _goToCheckout,
                    ),
                  ),
                ],
              ),
            ),
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
    final cs = Theme.of(context).colorScheme;
    final hasSelection = selectedCount > 0;
    return Container(
      height: _selectionRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFE8EDF5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedText(selectedCount),
              style: TextStyle(
                fontSize: NataloTextSize.bodyLg,
                fontWeight: NataloWeight.body,
                color: hasSelection ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            onPressed: hasSelection ? onDeleteSelected : null,
            tooltip: 'Hapus terpilih',
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 22,
              color: hasSelection ? cs.onSurface : cs.onSurfaceVariant,
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

    final cs = Theme.of(context).colorScheme;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: cs.surface,
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
              style: TextStyle(
                color: cs.onSurface,
                fontSize: NataloTextSize.subtitle,
                fontWeight: NataloWeight.strong,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: NataloTextSize.body,
                fontWeight: NataloWeight.body,
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
                          fontSize: NataloTextSize.bodyLg,
                          fontWeight: NataloWeight.strong,
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
                          fontSize: NataloTextSize.bodyLg,
                          fontWeight: NataloWeight.strong,
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
/// Banner ringkas di atas list cart saat ada item stok habis.
class _CartStockBanner extends StatelessWidget {
  final int count;
  const _CartStockBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFDC2626);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count produk stok habis dan tidak ikut checkout. Hapus atau ganti varian.',
              style: const TextStyle(
                color: accent,
                fontSize: NataloTextSize.caption,
                fontWeight: NataloWeight.body,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge stok di cart item — "Stok habis" (merah) atau "Sisa N" (amber).
/// Warna pakai tint-alpha agar kebaca di light & dark.
class _StockBadge extends StatelessWidget {
  final bool outOfStock;
  final int availableStock;
  const _StockBadge({required this.outOfStock, required this.availableStock});

  @override
  Widget build(BuildContext context) {
    final accent =
        outOfStock ? const Color(0xFFDC2626) : const Color(0xFFB45309);
    final label =
        outOfStock ? 'Stok habis' : 'Sisa $availableStock — segera checkout';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            outOfStock
                ? Icons.remove_shopping_cart_outlined
                : Icons.inventory_2_outlined,
            size: 12,
            color: accent,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: NataloTextSize.micro,
              fontWeight: NataloWeight.strong,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final int index;
  final bool selected;
  final VoidCallback onToggleSelected;

  /// Isu stok dari validasi server (null = aman). `removed` → stok habis
  /// (tidak bisa checkout, auto-deselect di parent), `reduced` → stok
  /// tersisa < qty (badge "Sisa N").
  final CartValidationIssue? stockIssue;

  /// Mainkan entrance (fade + translate) hanya saat kartu pertama muncul.
  /// False untuk kartu yang disisipkan setelah mount (add dari rekomendasi)
  /// supaya tidak ada motion 220ms di tepi grid.
  final bool animateEntrance;

  const _CartItemCard({
    required this.item,
    required this.index,
    required this.selected,
    required this.onToggleSelected,
    this.stockIssue,
    this.animateEntrance = true,
  });

  void _removeWithUndo(BuildContext context) {
    cartStore.remove(item.key);
    _showCartDeleteSnackBar(
      context,
      message: 'Produk telah dihapus',
      onUndo: () => cartStore.restore(item, index: index),
      imageUrl: item.product.imageUrl,
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
    final picked = await ProductVariantPickerSheet.show(
      context,
      productSlug: item.product.slug,
      preselectedVariant: item.variant,
      confirmLabel: 'Simpan',
      confirmColor: _shippingGreen,
    );
    if (picked == null) return;
    // Variant swap = remove old cart item + add product dengan variant
    // baru, qty SAMA seperti sebelumnya. cartStore.addItem auto-merge
    // kalau variantId sudah ada di cart (increment qty existing).
    await cartStore.remove(item.key);
    await cartStore.addProduct(
      picked.product,
      variant: picked.variant,
      variantLabel: _composeVariantLabel(picked.product, picked.variant),
      quantity: item.quantity,
    );
  }

  String? _composeVariantLabel(Product product, ProductVariant variant) {
    return cartVariantOptionLabel(product, variant);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outOfStock = stockIssue?.isOutOfStock ?? false;
    final reduced = stockIssue?.isReduced ?? false;
    // Stok efektif untuk cap stepper — pakai availableStock dari server
    // kalau ada isu, else effectiveStock lokal.
    final availableStock = stockIssue?.availableStock ?? item.effectiveStock;
    final price = item.effectivePrice;
    final regular = item.variant?.price.toDouble() ?? item.product.price;
    final hasDiscount = regular > price;
    final discountPercent =
        hasDiscount ? (((regular - price) / regular) * 100).round() : 0;
    ProductVariant? labelVariant = item.variant;
    if (labelVariant != null && labelVariant.optionIds.isEmpty) {
      final variantId = labelVariant.id;
      for (final variant in item.product.variants) {
        if (variant.id == variantId) {
          labelVariant = variant;
          break;
        }
      }
    }
    final optionVariantLabel = labelVariant == null
        ? null
        : cartVariantOptionLabel(item.product, labelVariant);
    final rawVariantLabel = item.variantLabel?.trim();
    final skuVariantLabel =
        labelVariant?.sku?.trim() ?? item.variant?.sku?.trim();
    final variantLabel =
        optionVariantLabel != null && optionVariantLabel.isNotEmpty
            ? optionVariantLabel
            : rawVariantLabel != null &&
                    rawVariantLabel.isNotEmpty &&
                    rawVariantLabel != skuVariantLabel
                ? rawVariantLabel
                : null;
    final hasVariantSelection = variantLabel != null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: animateEntrance
          ? Duration(milliseconds: 220 + (index * 35).clamp(0, 180))
          : Duration.zero,
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
          color: cs.surface,
          // Padding kiri ringkas (4px) supaya checkbox nempel kiri ala
          // Tokopedia. Vertical 12 (sedikit lebih ringkas dari 14).
          padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox kiri.
              // Stok habis → checkbox dikunci & tidak tercentang (item ini
              // di-auto-deselect di parent supaya tidak ikut checkout).
              Checkbox(
                value: outOfStock ? false : selected,
                activeColor: _brandBlue,
                onChanged: outOfStock ? null : (_) => onToggleSelected(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              // Product image — soft bg, no border. Dibuat lebih besar agar
              // varian visual produk lebih mudah dikenali di cart. Di-dim +
              // overlay "Stok habis" saat out-of-stock.
              Opacity(
                opacity: outOfStock ? 0.45 : 1,
                child: InkWell(
                  onTap: () => _openProductDetail(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AppProductImage(
                      imageUrl: item.product.imageUrl,
                      fit: BoxFit.cover,
                      // Kartu sudah di-fade oleh entrance (atau muncul instan
                      // saat insert) → matikan cross-fade internal biar tidak
                      // dobel-fade di tepi grid.
                      fadeInDuration: Duration.zero,
                    ),
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
                        style: TextStyle(
                          color:
                              outOfStock ? cs.onSurfaceVariant : cs.onSurface,
                          fontSize: NataloTextSize.bodyLg,
                          height: 1.3,
                          fontWeight: NataloWeight.strong,
                        ),
                      ),
                    ),
                    // Badge stok: habis (merah) / sisa-N (amber). Full
                    // opacity walau item lain di-dim — ini sinyal penting.
                    if (outOfStock || reduced) ...[
                      const SizedBox(height: 6),
                      _StockBadge(
                        outOfStock: outOfStock,
                        availableStock: availableStock,
                      ),
                    ],
                    // Variant chip — tampil kalau item menyimpan pilihan
                    // varian, termasuk cart lama yang product snapshot-nya
                    // partial dari server.
                    // Tap → buka bottom sheet variant picker untuk ganti.
                    if (hasVariantSelection) ...[
                      const SizedBox(height: 8),
                      _VariantChipDropdown(
                        label: variantLabel,
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
                              SizedBox(
                                width: double.infinity,
                                height: 23,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    formatRupiah(price),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: hasDiscount
                                          ? const Color(0xFFEF4444)
                                          : cs.onSurface,
                                      fontSize: NataloTextSize.subtitle,
                                      fontWeight: NataloWeight.strong,
                                    ),
                                  ),
                                ),
                              ),
                              if (hasDiscount) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        formatRupiah(regular),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: NataloTextSize.caption,
                                          fontWeight: NataloWeight.body,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$discountPercent%',
                                      style: const TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: NataloTextSize.caption,
                                        fontWeight: NataloWeight.strong,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Stok habis → stepper diganti tombol "Hapus" supaya
                        // user bisa bersihkan item mati dari cart. Reduced →
                        // stepper tetap, tapi maxQty di-cap ke stok tersisa.
                        if (outOfStock)
                          TextButton.icon(
                            onPressed: () => _removeWithUndo(context),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18),
                            label: const Text('Hapus'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        else
                          _QtyStepper(
                            quantity: item.quantity,
                            maxQty:
                                reduced ? availableStock : item.effectiveStock,
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
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
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: NataloTextSize.body,
                  fontWeight: NataloWeight.body,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
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
    final cs = Theme.of(context).colorScheme;
    final canIncrement = widget.quantity < widget.maxQty;
    final decrementIsDelete = widget.quantity <= 1;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperCell(
            onTap: widget.onDecrement,
            child: decrementIsDelete
                ? Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  )
                : Text(
                    '−',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: NataloTextSize.title,
                      fontWeight: NataloWeight.strong,
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
              style: TextStyle(
                color: cs.onSurface,
                fontSize: NataloTextSize.bodyLg,
                fontWeight: NataloWeight.strong,
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
                color: canIncrement ? cs.onSurfaceVariant : cs.outlineVariant,
                fontSize: NataloTextSize.title,
                fontWeight: NataloWeight.strong,
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
  String? imageUrl,
}) {
  AppToast.showCartDeleted(
    context,
    message,
    duration: const Duration(milliseconds: 1400),
    onUndo: onUndo,
    imageUrl: imageUrl,
  );
}

bool _isCartShippingVoucherData(MemberVoucher voucher) {
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

/// Judul display voucher gratis-ongkir. Brand-eksklusif -> "Gratis Ongkir
/// dari {brand}" (pakai nama brand asli, bukan judul admin/kode); selain
/// itu pakai judul voucher apa adanya.
String _shippingVoucherDisplayTitle(MemberVoucher voucher) {
  final brand = voucher.brandName?.trim();
  if (voucher.isBrandExclusive && brand != null && brand.isNotEmpty) {
    return 'Gratis Ongkir dari $brand';
  }
  return voucher.title;
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
  final MemberVoucher? loyaltyVoucher;
  final bool shippingSelected;
  final bool remove;

  const _CartVoucherChoice._({
    this.shippingCode,
    this.discountVoucher,
    this.loyaltyVoucher,
    this.shippingSelected = false,
    this.remove = false,
  });

  factory _CartVoucherChoice.combined({
    required MemberVoucher? discountVoucher,
    required MemberVoucher? loyaltyVoucher,
    required bool shippingSelected,
    String? shippingCode,
  }) {
    return _CartVoucherChoice._(
      shippingCode: shippingCode,
      discountVoucher: discountVoucher,
      loyaltyVoucher: loyaltyVoucher,
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
  final String shippingText;
  final VoidCallback? onTap;

  const _StickyVoucherBar({
    required this.hasSelection,
    required this.loading,
    required this.discountVoucher,
    required this.discountAmount,
    required this.shippingSelected,
    required this.shippingDiscount,
    required this.shippingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // hasDiscount predicate hanya cek amount > 0 (sebelumnya juga cek
    // discountVoucher != null, tapi sekarang loyalty voucher di-track
    // di slot terpisah, jadi cuma cek total discount aja).
    final cs = Theme.of(context).colorScheme;
    final hasDiscount = discountAmount > 0;
    final hasShipping = shippingSelected;
    final leadingColor = hasSelection ? _discountRed : cs.onSurfaceVariant;
    final leadingBackground =
        hasSelection ? _discountRedSoft : cs.surfaceContainerHighest;
    final leadingBorder = hasSelection ? _discountRedBorder : cs.outlineVariant;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? cs.surface : const Color(0xFFF8FAFC),
      child: Container(
        height: _voucherBarHeight,
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(
              color: isDark ? cs.outlineVariant : const Color(0xFFE5EAF1),
            ),
          ),
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
                    Icons.confirmation_number_rounded,
                    color: leadingColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Voucher',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: NataloTextSize.body,
                    fontWeight: NataloWeight.strong,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _VoucherBenefitChips(
                      hasShipping: hasShipping,
                      shippingText: shippingText,
                      hasDiscount: hasDiscount,
                      discountText: '-${formatRupiah(discountAmount)}',
                      loading: loading,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  color: hasSelection ? cs.onSurfaceVariant : cs.outlineVariant,
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
        ),
      );
    }
    if (chips.isEmpty) {
      chips.add(
        _VoucherMiniChip(
          text: loading ? 'Cek...' : 'Pilih',
          color: _brandBlue,
          background: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
              : const Color(0xFFEAF5FF),
          border: const Color(0xFFBFDBFE),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 186),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        physics: const BouncingScrollPhysics(),
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

  const _VoucherMiniChip({
    required this.text,
    required this.color,
    required this.background,
    required this.border,
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
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: NataloTextSize.micro,
              fontWeight: NataloWeight.strong,
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
  final String? selectedDiscountCode;
  final String? selectedLoyaltyCode;
  final String? selectedShippingCode;
  final bool shippingSelected;
  final bool isManual;
  final bool loading;

  const _CartVoucherSheet({
    required this.availableDiscounts,
    required this.unavailableDiscounts,
    required this.selectedDiscountCode,
    required this.selectedLoyaltyCode,
    required this.selectedShippingCode,
    required this.shippingSelected,
    required this.isManual,
    required this.loading,
  });

  @override
  State<_CartVoucherSheet> createState() => _CartVoucherSheetState();
}

class _CartVoucherSheetState extends State<_CartVoucherSheet> {
  // 3 slot terpisah supaya user bisa pakai 1 ongkir + 1 diskon produk +
  // 1 reward poin bersamaan (sesuai business rule Natalo). Sebelumnya
  // cuma punya 1 slot `_selectedDiscount` yang dipake bareng untuk
  // product DAN loyalty → user tap reward poin auto-deselect diskon
  // produk yang udah dipilih, dan vice versa.
  String? _selectedShippingCode;
  MemberVoucher? _selectedProductDiscount;
  MemberVoucher? _selectedLoyalty;

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
      } else if (selectedVoucher != null && selectedVoucher.isLoyaltyClaim) {
        // Defensive — legacy code path bisa kirim loyalty voucher ke
        // selectedDiscountCode. Route ke slot yang benar.
        _selectedLoyalty = selectedVoucher;
      } else {
        for (final voucher in widget.availableDiscounts) {
          if (voucher.code == widget.selectedDiscountCode) {
            _selectedProductDiscount = voucher;
            break;
          }
        }
      }
    }

    if (widget.selectedLoyaltyCode != null) {
      for (final voucher in widget.availableDiscounts) {
        if (voucher.code == widget.selectedLoyaltyCode &&
            voucher.isLoyaltyClaim) {
          _selectedLoyalty = voucher;
          break;
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
    return null;
  }

  /// Route pick ke slot yang sesuai type. Loyalty voucher masuk slot
  /// loyalty, product discount masuk slot product. Tap-yang-sama =
  /// deselect; tap-yang-beda di slot sama = swap.
  void _pickDiscount(MemberVoucher voucher) {
    setState(() {
      if (voucher.isLoyaltyClaim) {
        if (_selectedLoyalty?.code == voucher.code) {
          _selectedLoyalty = null;
        } else {
          _selectedLoyalty = voucher;
        }
      } else {
        if (_selectedProductDiscount?.code == voucher.code) {
          _selectedProductDiscount = null;
        } else {
          _selectedProductDiscount = voucher;
        }
      }
    });
  }

  void _pickShipping(String code) {
    setState(() {
      _selectedShippingCode = _selectedShippingCode == code ? null : code;
    });
  }

  void _applySelection() {
    Navigator.pop(
      context,
      _CartVoucherChoice.combined(
        discountVoucher: _selectedProductDiscount,
        loyaltyVoucher: _selectedLoyalty,
        shippingSelected: _selectedShippingCode != null,
        shippingCode: _selectedShippingCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
    final hasAnyVoucher = availableShippingVouchers.isNotEmpty ||
        availableProductVouchers.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return GlassSurface(
          radius: 28,
          tint: cs.surface,
          padding: EdgeInsets.fromLTRB(18, 14, 18, 14 + bottomInset),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih voucher atau promo',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: NataloTextSize.title,
                        fontWeight: NataloWeight.strong,
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
                      fontSize: NataloTextSize.caption,
                      fontWeight: NataloWeight.strong,
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
                    for (final voucher in availableShippingVouchers) ...[
                      _CartVoucherCard(
                        title: _shippingVoucherDisplayTitle(voucher),
                        subtitle: _cartShippingVoucherSubtitle(voucher, 0),
                        badge: 'Ongkir',
                        brandExclusive: voucher.isBrandExclusive,
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
                        // Brand-exclusive selalu badge nama brand + oranye,
                        // di atas prioritas loyalty/diskon biasa. Loyalty
                        // voucher = "Reward Poin" badge + star purple match
                        // styling checkout. Product discount = "Diskon" tag
                        // pink. Differentiate icon supaya user paham type
                        // voucher langsung dari visual.
                        badge: voucher.isBrandExclusive
                            ? 'Brand Eksklusif'
                            : voucher.isLoyaltyClaim
                                ? 'Reward Poin'
                                : 'Diskon',
                        trailing: formatRupiah(voucher.discount),
                        icon: voucher.isBrandExclusive
                            ? Icons.workspace_premium_rounded
                            : voucher.isLoyaltyClaim
                                ? Icons.stars_rounded
                                : Icons.local_offer_rounded,
                        accent: voucher.isBrandExclusive
                            ? _brandExclusiveAmber
                            : voucher.isLoyaltyClaim
                                ? _loyaltyPurple
                                : _discountRed,
                        background: voucher.isBrandExclusive
                            ? _brandExclusiveAmberSoft
                            : voucher.isLoyaltyClaim
                                ? _loyaltyPurpleSoft
                                : _discountRedSoft,
                        border: voucher.isBrandExclusive
                            ? _brandExclusiveAmberBorder
                            : voucher.isLoyaltyClaim
                                ? _loyaltyPurpleBorder
                                : _discountRedBorder,
                        selected: voucher.isLoyaltyClaim
                            ? _selectedLoyalty?.code == voucher.code
                            : _selectedProductDiscount?.code == voucher.code,
                        enabled: true,
                        onTap: () => _pickDiscount(voucher),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (!hasAnyVoucher && !widget.loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          'Belum ada voucher yang cocok',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: NataloWeight.strong,
                          ),
                        ),
                      ),
                    if (unavailableShippingVouchers.isNotEmpty ||
                        unavailableProductVouchers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Belum bisa dipakai',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: NataloTextSize.caption,
                          fontWeight: NataloWeight.strong,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final voucher in unavailableShippingVouchers) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              _cartShippingVoucherSubtitle(voucher, 0),
                          badge: 'Ongkir',
                          brandExclusive: voucher.isBrandExclusive,
                          trailing: voucher.discount > 0
                              ? formatRupiah(voucher.discount)
                              : null,
                          icon: Icons.local_shipping_outlined,
                          accent: _shippingGreen,
                          background: cs.surfaceContainerHighest,
                          border: cs.outlineVariant,
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
                          badge: voucher.isBrandExclusive
                              ? 'Brand Eksklusif'
                              : voucher.isLoyaltyClaim
                                  ? 'Reward Poin'
                                  : 'Diskon',
                          trailing: voucher.discount > 0
                              ? formatRupiah(voucher.discount)
                              : null,
                          icon: voucher.isBrandExclusive
                              ? Icons.workspace_premium_rounded
                              : voucher.isLoyaltyClaim
                                  ? Icons.stars_rounded
                                  : Icons.local_offer_outlined,
                          accent: voucher.isBrandExclusive
                              ? _brandExclusiveAmber
                              : voucher.isLoyaltyClaim
                                  ? _loyaltyPurple
                                  : _discountRed,
                          background: cs.surfaceContainerHighest,
                          border: cs.outlineVariant,
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
                      onPressed: _selectedProductDiscount == null &&
                              _selectedLoyalty == null &&
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
                        style: TextStyle(fontWeight: NataloWeight.strong),
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
  final bool brandExclusive;

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
    this.brandExclusive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveAccent = enabled ? accent : cs.onSurfaceVariant;
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                            fontSize: NataloTextSize.micro,
                            fontWeight: NataloWeight.strong,
                          ),
                        ),
                      ),
                      if (brandExclusive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _brandExclusiveAmberSoft,
                            borderRadius: BorderRadius.circular(999),
                            border:
                                Border.all(color: _brandExclusiveAmberBorder),
                          ),
                          child: const Text(
                            'Brand Eksklusif',
                            style: TextStyle(
                              color: _brandExclusiveAmber,
                              fontSize: NataloTextSize.micro,
                              fontWeight: NataloWeight.strong,
                            ),
                          ),
                        ),
                      if (selected)
                        Text(
                          'Terpilih',
                          style: TextStyle(
                            color: accent,
                            fontSize: NataloTextSize.micro,
                            fontWeight: NataloWeight.strong,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                      fontSize: NataloTextSize.bodyLg,
                      fontWeight: NataloWeight.strong,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          enabled ? cs.onSurfaceVariant : cs.onSurfaceVariant,
                      fontSize: NataloTextSize.caption,
                      fontWeight: NataloWeight.body,
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
                  fontSize: NataloTextSize.caption,
                  fontWeight: NataloWeight.strong,
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
                      ? cs.outlineVariant
                      : cs.outlineVariant,
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
    super.key,
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

    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Judul di-padding sendiri (parent section ini sekarang horizontal 0
        // supaya latar abu grid bisa nempel tepi layar / full-bleed).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: NataloTextSize.subtitle,
                    fontWeight: NataloWeight.strong,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Latar abu full-bleed di belakang grid — kartu putih foto 1:1
        // menonjol, sama Beranda/Katalog/Wishlist.
        ColoredBox(
          color: commerceGridSurfaceTint(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: (loading && showLoadingPlaceholder)
                // Skeleton row auto-height + square (anti overflow).
                ? const SkeletonProductGrid(
                    count: 4, showAddToCart: true, squareImage: true)
                : Column(
                    children: [
                      // Grid 2-kolom AUTO-HEIGHT — tinggi baris ikut konten.
                      // WAJIB CrossAxisAlignment.start (JANGAN .stretch →
                      // intrinsic-height exception ditelan → section blank).
                      // Lihat catatan lengkap di products_screen.dart.
                      for (var row = 0; row < (products.length + 1) ~/ 2; row++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                row == (products.length + 1) ~/ 2 - 1 ? 0 : 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildCard(context, products[row * 2]),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: row * 2 + 1 < products.length
                                    ? _buildCard(context, products[row * 2 + 1])
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      if (loadingMore && showLoadingPlaceholder) ...[
                        const SizedBox(height: 6),
                        const SkeletonProductGrid(
                            count: 2, showAddToCart: true, squareImage: true),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, Product product) {
    return CompactCommerceProductCard(
      product: product,
      squareImage: true,
      onTap: () {
        AppHaptics.tap();
        Navigator.pushNamed(
          context,
          '/product-detail',
          arguments: product,
        );
      },
      onAddToCart: () {
        if (product.hasVariants) {
          AppHaptics.tap();
          Navigator.pushNamed(
            context,
            '/product-detail',
            arguments: product,
          );
          AppToast.show(
            context,
            'Pilih varian produk dulu.',
            kind: ToastKind.info,
          );
          return;
        }
        AppHaptics.success();
        cartStore.addProduct(product);
        AppToast.showCartAdded(
          context,
          '${product.title} masuk keranjang',
          imageUrl: product.imageUrl,
        );
      },
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
    final cs = Theme.of(context).colorScheme;
    final checkoutLabel =
        disabled ? 'Checkout' : 'Checkout ($selectedQuantity)';
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? cs.surface
          : const Color(0xFFF8FAFC),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant, width: 1),
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
                      Text(
                        'Belum ada pilihan',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: NataloTextSize.title,
                          fontWeight: NataloWeight.strong,
                        ),
                      )
                    else ...[
                      // Label "Subtotal" — jelaskan angka ini BUKAN total
                      // bayar final (ongkir + total lengkap di checkout).
                      Text(
                        'Subtotal',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: NataloTextSize.micro,
                          fontWeight: NataloWeight.body,
                        ),
                      ),
                      AnimatedRupiah(
                        value: grandTotal,
                        style: NataloTextStyles.totalPaymentPrice.copyWith(
                          // Adaptif dark: priceText (slate gelap) invisible di
                          // surface gelap → resolve via onSurface.
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: NataloTextSize.title,
                          fontWeight: NataloWeight.strong,
                        ),
                      ),
                    ],
                    if (!disabled && totalSaving > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Total Hemat ${formatRupiah(totalSaving)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _discountRed,
                          fontSize: NataloTextSize.caption,
                          fontWeight: NataloWeight.strong,
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
              if (product.hasVariants) {
                AppHaptics.tap();
                Navigator.pushNamed(
                  context,
                  '/product-detail',
                  arguments: product,
                );
                AppToast.show(
                  context,
                  'Pilih varian produk dulu.',
                  kind: ToastKind.info,
                );
                return;
              }
              cartStore.addProduct(product);
              AppToast.showCartAdded(
                context,
                '${product.title} masuk keranjang',
                actionLabel: 'Lihat Keranjang',
                onTap: () => Navigator.pushNamed(context, '/cart'),
                imageUrl: product.imageUrl,
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
              if (product.hasVariants) {
                AppHaptics.tap();
                Navigator.pushNamed(
                  context,
                  '/product-detail',
                  arguments: product,
                );
                AppToast.show(
                  context,
                  'Pilih varian produk dulu.',
                  kind: ToastKind.info,
                );
                return;
              }
              cartStore.addProduct(product);
              AppToast.showCartAdded(
                context,
                '${product.title} masuk keranjang',
                actionLabel: 'Lihat Keranjang',
                onTap: () => Navigator.pushNamed(context, '/cart'),
                imageUrl: product.imageUrl,
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
      decoration: BoxDecoration(
        color: cs.surface,
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
          Text(
            'Keranjang kamu masih kosong',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NataloTextSize.headline,
              height: 1.18,
              fontWeight: NataloWeight.strong,
              color: cs.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Yuk pilih makanan, vitamin, pasir, atau perlengkapan\nfavorit untuk hewan kesayanganmu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NataloTextSize.subtitle,
              height: 1.45,
              fontWeight: NataloWeight.body,
              color: cs.onSurfaceVariant,
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
                  fontSize: NataloTextSize.subtitle,
                  fontWeight: NataloWeight.strong,
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

    final cs = Theme.of(context).colorScheme;
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
                  style: TextStyle(
                    fontSize: NataloTextSize.title,
                    fontWeight: NataloWeight.strong,
                    color: cs.onSurface,
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
                        fontSize: NataloTextSize.subtitle,
                        fontWeight: NataloWeight.strong,
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
                // Foto 1:1 cover penuh (spec grid) — carousel keranjang-kosong
                // pun menonjol ala Shopee. Tinggi carousel (336) muat.
                squareImage: true,
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
