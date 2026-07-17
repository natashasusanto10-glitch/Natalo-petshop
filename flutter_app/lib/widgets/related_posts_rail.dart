import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'scaled_video_feed_route.dart';

/// Deteksi apakah binding aktif adalah `TestWidgetsFlutterBinding` tanpa
/// mengimpor `package:flutter_test` ke kode produksi (dilarang di lib/).
/// `flutter_test` mendaftarkan binding dengan nama runtime yang mengandung
/// "Test" (mis. `AutomatedTestWidgetsFlutterBinding`), sedangkan binding asli
/// di device selalu `WidgetsFlutterBinding`.
bool _isTestBinding() =>
    WidgetsBinding.instance.runtimeType.toString().contains('Test');

/// Tunggu satu frame selesai: sinkron via `drawFrame()` di harness test
/// (tak ada engine yang men-drive vsync di sana), atau lewat penjadwalan
/// frame normal (vsync) di device sungguhan agar tidak reentrant/jank.
Future<void> _flushFrame() async {
  if (_isTestBinding()) {
    WidgetsBinding.instance.drawFrame();
  } else {
    WidgetsBinding.instance.scheduleFrame();
    await SchedulerBinding.instance.endOfFrame;
  }
}

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
  ///
  /// Catatan: fungsi ini bisa melakukan beberapa kali frame flush sinkron
  /// (lihat [_flushFrame]) untuk memaksa kartu di luar layar termaterialisasi
  /// sebelum rect-nya bisa diukur.
  Future<ScaledVideoFeedReverseTarget?> resolveReturnTarget(
    String postId, {
    required String imageUrl,
    double borderRadius = 14,
  }) async {
    try {
      var context = _keys[postId]?.currentContext;
      // Kartu jauh (mis. id ke-18 dari 20) belum pernah dibangun oleh
      // ListView.builder yang lazy — geser bertahap sampai kartunya masuk
      // viewport/cache-extent dan itemBuilder membuat key-nya.
      context ??= await _scrollUntilBuilt(postId);
      if (context == null || !context.mounted) return null;

      await Scrollable.ensureVisible(
        context,
        duration: Duration.zero,
        alignment: 0.5,
      );
      // Paksa layout yang tertunda (dipicu oleh jump di atas) berjalan
      // sebelum rect diukur — lihat dokumentasi [_flushFrame].
      await _flushFrame();

      final box =
          _keys[postId]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return ScaledVideoFeedReverseTarget(
        rect: box.localToGlobal(Offset.zero) & box.size,
        imageUrl: imageUrl,
        borderRadius: borderRadius,
      );
    } catch (_) {
      // Kegagalan device-only mid-close (mis. controller sudah disposed)
      // tidak boleh merusak alur morph-close user-facing — jatuh ke null
      // supaya route memakai morph default yang aman.
      return null;
    }
  }

  /// Geser [scroll] setahap demi setahap (selebar viewport) sampai kartu
  /// [postId] ter-render, atau sampai mentok akhir daftar.
  Future<BuildContext?> _scrollUntilBuilt(String postId) async {
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
      await _flushFrame();
      found = _keys[postId]?.currentContext;
      if (target >= maxExtent) break;
    }
    return found;
  }

  void dispose() => scroll.dispose();
}
