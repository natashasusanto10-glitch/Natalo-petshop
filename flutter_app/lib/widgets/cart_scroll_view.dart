import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Scroll view keranjang berbasis **center-sliver**.
///
/// Blok cart-items ada di sliver **SEBELUM** center; rekomendasi ada **DI**
/// center. Menyisipkan item ke cart (di atas center) tidak menggeser
/// rekomendasi yang sedang dilihat — bebas loncat **by-design**, tanpa
/// aritmetika pixel / estimasi `maxScrollExtent`.
///
/// Kenapa bukan `ListView` + koreksi pixel (v165–v170): `RenderSliverList`
/// pixel-anchored pada insert-di-atas, dan `maxScrollExtent`-nya ESTIMASI
/// lazy (grid rekomendasi raksasa + load-more + decode gambar), jadi koreksi
/// berbasis selisih maxExtent meleset → loncat ~1 kartu tiap add. Center-sliver
/// memindahkan invarian "yang dilihat tidak bergeser" ke geometri native.
class CartScrollView extends StatefulWidget {
  const CartScrollView({
    super.key,
    required this.controller,
    required this.itemIds,
    required this.itemBuilder,
    required this.center,
    this.leadingSlivers = const <Widget>[],
    this.cacheExtent = 600,
  });

  final ScrollController controller;

  /// Id stabil tiap item, urutan penyimpanan (lama→baru). Item TERBARU (akhir
  /// list) dirender paling BAWAH blok cart (tepat di atas rekomendasi).
  final List<String> itemIds;

  /// Bangun konten baris untuk `dataIndex` (0 = item terlama = paling atas).
  /// Root widget di-wrap `KeyedSubtree` oleh CartScrollView — JANGAN pasang
  /// key sendiri di root (boleh di dalam).
  final Widget Function(BuildContext context, int dataIndex) itemBuilder;

  /// Sliver-sliver sebelum blok cart (mis. spacer, banner stok). Ikut sisi
  /// SEBELUM center → tumbuh/susutnya tidak menggeser rekomendasi.
  final List<Widget> leadingSlivers;

  /// Konten rekomendasi (satu box) yang menjadi center/anchor.
  final Widget center;

  final double cacheExtent;

  @override
  State<CartScrollView> createState() => _CartScrollViewState();
}

class _CartScrollViewState extends State<CartScrollView> {
  static const _centerKey = ValueKey<String>('cart-center-anchor');
  bool _anchored = false;

  @override
  void initState() {
    super.initState();
    _anchorToTop();
  }

  /// Center-sliver membuka pada offset 0 = TOP rekomendasi. Kita mau tampil
  /// dari kartu cart paling atas → `jumpTo(minScrollExtent)`. `min` bisa
  /// refine setelah kartu atas benar-benar ter-layout, jadi ulangi sampai
  /// stabil (bounded, sekali di awal saja — tak mengganggu scroll user).
  void _anchorToTop([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchored) return;
      final controller = widget.controller;
      if (!controller.hasClients || !controller.position.hasContentDimensions) {
        if (attempt < 6) _anchorToTop(attempt + 1);
        return;
      }
      final position = controller.position;
      final min = position.minScrollExtent;
      if ((position.pixels - min).abs() > 0.5) {
        controller.jumpTo(min);
        if (attempt < 6) {
          _anchorToTop(attempt + 1);
          return;
        }
      }
      _anchored = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.itemIds;
    final count = ids.length;
    return CustomScrollView(
      controller: widget.controller,
      center: _centerKey,
      scrollCacheExtent: ScrollCacheExtent.pixels(widget.cacheExtent),
      slivers: [
        // ── SEBELUM center (urutan sliver = visual atas→bawah) ──
        ...widget.leadingSlivers,
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, sliverIndex) {
              // Di sliver sebelum-center, child index 0 = paling DEKAT center
              // = paling BAWAH. Balik: dataIndex terbaru (akhir) → sliver 0.
              final dataIndex = count - 1 - sliverIndex;
              return KeyedSubtree(
                key: ValueKey<String>('cart-row-${ids[dataIndex]}'),
                child: widget.itemBuilder(context, dataIndex),
              );
            },
            childCount: count,
            // WAJIB: append ke itemIds menggeser SEMUA sliverIndex; tanpa ini
            // reconciliation by-index me-rebuild subtree kartu (re-shimmer).
            // Cocokkan by-key → identitas element stabil.
            findChildIndexCallback: (key) {
              final value = (key as ValueKey).value;
              if (value is! String || !value.startsWith('cart-row-')) {
                return null;
              }
              final id = value.substring('cart-row-'.length);
              final dataIndex = ids.indexOf(id);
              if (dataIndex < 0) return null;
              return count - 1 - dataIndex;
            },
          ),
        ),
        // ── CENTER (scrollOffset 0 = top rekomendasi) ──
        SliverToBoxAdapter(key: _centerKey, child: widget.center),
      ],
    );
  }
}
