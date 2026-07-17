import 'package:flutter/material.dart';

import 'scaled_video_feed_route.dart';

/// Koordinator kecil untuk rail "Postingan Terkait": menyimpan key stabil
/// per-post sehingga kartu manapun bisa menemukan rect kartu lain, dan
/// menyediakan target morph-balik saat viewer video ditutup.
class RelatedPostsRail {
  final ScrollController scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};

  /// Key stabil (memoized) untuk thumbnail sebuah post.
  GlobalKey keyFor(String postId) =>
      _keys.putIfAbsent(postId, () => GlobalKey());

  /// Scroll kartu [postId] agar terlihat, ukur rect-nya, dan bangun target
  /// morph-balik. Mengembalikan null bila kartu tidak ter-render (mis. post
  /// dari load-more yang belum ada di rail) — route jatuh ke morph default.
  Future<ScaledVideoFeedReverseTarget?> resolveReturnTarget(
    String postId, {
    required String imageUrl,
    double borderRadius = 14,
  }) async {
    var context = _keys[postId]?.currentContext;
    // Kartu jauh (mis. id ke-18 dari 20) belum pernah dibangun oleh
    // ListView.builder yang lazy — geser bertahap sampai kartunya masuk
    // viewport/cache-extent dan itemBuilder membuat key-nya.
    context ??= _scrollUntilBuilt(postId);
    if (context == null) return null;

    await Scrollable.ensureVisible(
      context,
      duration: Duration.zero,
      alignment: 0.5,
    );
    // Paksa layout yang tertunda (dipicu oleh jump di atas) berjalan
    // sinkron alih-alih menunggu frame berikutnya dari engine: pemakaian
    // nyata terjadi di luar tap user (tak ada frame yang berjalan), dan di
    // harness widget-test frame tak pernah di-pump implisit, sehingga
    // menunggu WidgetsBinding.endOfFrame akan menggantung selamanya.
    WidgetsBinding.instance.drawFrame();

    final box = _keys[postId]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return ScaledVideoFeedReverseTarget(
      rect: box.localToGlobal(Offset.zero) & box.size,
      imageUrl: imageUrl,
      borderRadius: borderRadius,
    );
  }

  /// Geser [scroll] setahap demi setahap (selebar viewport) sampai kartu
  /// [postId] ter-render, atau sampai mentok akhir daftar.
  BuildContext? _scrollUntilBuilt(String postId) {
    if (!scroll.hasClients) return null;
    final position = scroll.position;
    final maxExtent = position.maxScrollExtent;
    final step =
        position.viewportDimension > 0 ? position.viewportDimension : 300.0;

    var target = scroll.offset;
    var found = _keys[postId]?.currentContext;
    while (found == null && target < maxExtent) {
      target = (target + step).clamp(0.0, maxExtent);
      scroll.jumpTo(target);
      WidgetsBinding.instance.drawFrame();
      found = _keys[postId]?.currentContext;
      if (target >= maxExtent) break;
    }
    return found;
  }

  void dispose() => scroll.dispose();
}
