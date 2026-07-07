import 'package:flutter/widgets.dart';

import 'scroll_anchor.dart';

/// [ScrollController] yang bisa mempertahankan posisi visual saat konten
/// bertambah DI ATAS viewport (mis. kartu item baru nyelip di keranjang),
/// dengan koreksi **IN-LAYOUT** (via [ScrollPosition.correctPixels] di dalam
/// `applyContentDimensions`, sebelum paint).
///
/// Kenapa bukan post-frame `jumpTo`: jumpTo mengoreksi SETELAH frame ter-paint
/// → menyisakan 1-frame "blip", DAN menotifikasi listener scroll → memicu
/// kaskade (auto-hide chrome, pagination load-more) yang bisa balapan &
/// menyebabkan loncat/gap. `correctPixels` di dalam layout tidak paint dulu
/// dan tidak menotifikasi listener → nol blip, tanpa kaskade.
///
/// Pemakaian: panggil [retainOffsetOnNextGrowth] TEPAT SEBELUM mutasi yang
/// menambah konten di atas (mis. `cartStore.addProduct`). Koreksi hanya
/// berlaku untuk pertumbuhan berikutnya, sekali. Tidak di-arm untuk
/// pertumbuhan di bawah (mis. load-more) sehingga append di bawah tetap natural.
class RetainableScrollController extends ScrollController {
  RetainableScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  _RetainableScrollPosition? _position;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    final position = _RetainableScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
    );
    _position = position;
    return position;
  }

  /// Arm koreksi in-layout untuk pertumbuhan konten berikutnya. No-op kalau
  /// belum ada viewport terpasang, atau (saat diterapkan) user di puncak
  /// sehingga [anchoredOffsetAfterInsert] mengembalikan null.
  void retainOffsetOnNextGrowth() {
    if (!hasClients) return;
    _position?.armRetain();
  }
}

class _RetainableScrollPosition extends ScrollPositionWithSingleContext {
  _RetainableScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  bool _retain = false;
  double? _oldPixels;
  double? _oldMaxExtent;

  /// Tangkap baseline (pixels + maxExtent) SEBELUM konten berubah. Skip kalau
  /// dimensi belum siap (tidak ada baseline yang valid).
  void armRetain() {
    if (!hasPixels || !hasContentDimensions) return;
    _retain = true;
    _oldPixels = pixels;
    _oldMaxExtent = maxScrollExtent;
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // Hanya bertindak (dan meng-consume arm) saat PERTUMBUHAN nyata terlihat.
    // Penting: applyContentDimensions bisa dipanggil dulu dengan maxExtent LAMA
    // sebelum geometri sisip selesai — kalau di-consume di situ, koreksi asli
    // terlewat. Guard `maxScrollExtent > oldMax` bikin arm bertahan sampai
    // growth beneran (pola RetainableScrollController yang teruji).
    final oldPixels = _oldPixels;
    final oldMax = _oldMaxExtent;
    if (_retain &&
        oldPixels != null &&
        oldMax != null &&
        maxScrollExtent > oldMax) {
      final target = anchoredOffsetAfterInsert(
        oldMaxExtent: oldMax,
        oldPixels: oldPixels,
        newMaxExtent: maxScrollExtent,
      );
      if (target != null) {
        final clamped = target.clamp(minScrollExtent, maxScrollExtent);
        // correctPixels di dalam applyContentDimensions = koreksi in-layout
        // sebelum paint, tanpa notifikasi listener.
        if ((clamped - pixels).abs() > 0.5) {
          correctPixels(clamped);
        }
      }
      _retain = false;
      _oldPixels = null;
      _oldMaxExtent = null;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
