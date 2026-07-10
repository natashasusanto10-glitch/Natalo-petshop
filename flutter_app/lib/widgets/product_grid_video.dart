import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'product_grid_video_registry.dart';

/// Video produk per-kartu untuk grid Beranda: foto 1:1 sebagai DASAR yang
/// selalu ada, dengan video bisu ber-loop yang fade-in di atasnya saat kartu
/// cukup terlihat (>=60%) DAN registry masih punya slot decoder.
///
/// Prinsip:
/// - Controller dibuat **lazy** (baru saat pertama terlihat), bukan di
///   `initState` — hemat decoder untuk kartu yang belum kelihatan.
/// - Di-gate `ProductGridVideoRegistry` (maks 3 controller aktif) supaya HP
///   tidak kehabisan decoder / janky.
/// - Dispose + release slot saat scroll-away, dan retry saat slot bebas.
/// - Geometri kartu TIDAK diubah: `AspectRatio(1)`, isi full-bleed tanpa radius
///   sendiri (kartu induk yang meng-clip) — identik `_HomeProductImageSquare`.
///
/// Model init/loop/volume dari `_InlineVideoPlayer` (member_post_detail_screen)
/// tapi lazy, registry-gated, dan race-guarded. HLS (.m3u8) WAJIB pakai plain
/// `VideoPlayerController.networkUrl` (bukan cached wrapper — segmen HLS tidak
/// ter-cache), plus `mixWithOthers: true` (tanpa ini autoplay bisu di iOS
/// menghentikan musik latar user).
class ProductGridVideo extends StatefulWidget {
  final String videoUrl;
  final String? imageUrl;

  const ProductGridVideo({
    super.key,
    required this.videoUrl,
    required this.imageUrl,
  });

  @override
  State<ProductGridVideo> createState() => _ProductGridVideoState();
}

class _ProductGridVideoState extends State<ProductGridVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// Fraksi visibilitas terakhir dari `VisibilityDetector` (0..1).
  double _visibleFraction = 0;

  /// True selama `initialize()` + setup sedang berjalan (ada `await` yang
  /// belum selesai). Dipakai supaya:
  /// - `_ensureAndPlay` tidak membuat controller kedua saat satu sedang init.
  /// - `_stopAndRelease` TIDAK men-dispose controller in-flight (race guard di
  ///   `_ensureAndPlay` yang akan dispose + release — kepemilikan tunggal,
  ///   cegah double-dispose).
  bool _acquiring = false;

  /// Apakah kita sedang terdaftar sebagai penunggu slot registry.
  bool _slotListenerRegistered = false;

  ProductGridVideoRegistry get _registry => ProductGridVideoRegistry.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAndRelease();
    _removeSlotListener();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Android/iOS auto-pause di background, tapi TIDAK auto-resume →
      // pause eksplisit supaya state kita akurat.
      unawaited(controller.pause());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      // Balik dari background: kalau masih cukup terlihat, main lagi (tanpa ini
      // grid balik dari background nyangkut di frame beku).
      if (_visibleFraction >= 0.6) {
        unawaited(controller.play());
        if (mounted) setState(() {});
      }
    }
  }

  // ─── Visibility → play/stop ─────────────────────────────────────────────

  void _onVisibilityChanged(VisibilityInfo info) {
    _visibleFraction = info.visibleFraction;
    if (_visibleFraction >= 0.6) {
      unawaited(_ensureAndPlay());
    } else {
      _stopAndRelease();
    }
  }

  /// Pastikan ada controller yang init & main. Lazy + registry-gated +
  /// race-guarded.
  Future<void> _ensureAndPlay() async {
    final existing = _controller;
    if (existing != null) {
      // Sudah ada controller — cukup pastikan main (mis. balik dari pause).
      if (existing.value.isInitialized && !existing.value.isPlaying) {
        unawaited(existing.play());
        if (mounted) setState(() {});
      }
      return;
    }
    if (_acquiring) return; // init sedang jalan — jangan bikin dua.

    // Butuh slot decoder. Kalau penuh → tetap foto, daftar untuk retry saat
    // slot bebas (JANGAN retry-loop).
    if (!_registry.tryAcquire(this)) {
      _addSlotListener();
      return;
    }

    _acquiring = true;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      // Race guard setelah SETIAP await: kalau widget sudah lepas atau
      // `_controller` sudah di-swap (mis. scroll-away nge-null-kan), buang
      // controller lokal ini — jangan pernah panggil method di controller yang
      // bukan `_controller` lagi.
      if (_isStale(controller)) return _abandon(controller);
      await controller.setLooping(true);
      if (_isStale(controller)) return _abandon(controller);
      await controller.setVolume(0);
      if (_isStale(controller)) return _abandon(controller);
      await controller.play();
      if (_isStale(controller)) return _abandon(controller);

      _acquiring = false;
      _removeSlotListener(); // slot aman & main — tak perlu nunggu lagi.
      if (mounted) setState(() {}); // fade video in.
    } catch (_) {
      // Init gagal (URL rusak / HLS hiccup) → tetap di foto, lepas slot,
      // JANGAN kotak hitam, JANGAN retry-loop.
      if (identical(_controller, controller)) _controller = null;
      _acquiring = false;
      unawaited(controller.dispose());
      _registry.release(this);
      if (mounted) setState(() {});
    }
  }

  /// True jika [controller] sudah bukan controller aktif kita (widget lepas
  /// atau `_controller` sudah di-swap oleh `_stopAndRelease`).
  bool _isStale(VideoPlayerController controller) =>
      !mounted || !identical(_controller, controller);

  /// Bersihkan controller yatim (di-swap saat init in-flight). Dipanggil oleh
  /// race guard — pemilik tunggal dispose untuk kasus ini.
  void _abandon(VideoPlayerController controller) {
    _acquiring = false;
    unawaited(controller.dispose());
    _registry.release(this);
    // Kalau ternyata masih cukup terlihat & idle (mis. scroll-away lalu balik
    // saat init in-flight), coba sekali lagi supaya tidak nyangkut di foto.
    // Ini BUKAN retry-loop error (path catch tidak memanggil ini) — hanya
    // menutup celah race swap saat kartu tetap on-screen.
    if (mounted && _visibleFraction >= 0.6 && _controller == null) {
      unawaited(_ensureAndPlay());
    }
  }

  /// Stop + lepas semua sumber daya, balik ke foto saja.
  void _stopAndRelease() {
    final controller = _controller;
    // Null-kan DULU supaya race guard di init in-flight melihat swap.
    _controller = null;
    if (controller != null) {
      if (_acquiring) {
        // Init masih in-flight: JANGAN dispose di sini — race guard
        // (`_abandon`) yang akan dispose + release saat await selesai. Dispose
        // ganda di sini = crash controller.
      } else {
        unawaited(controller.pause());
        unawaited(controller.dispose());
        _registry.release(this);
      }
    }
    _removeSlotListener();
    if (mounted) setState(() {});
  }

  /// Slot registry bebas → coba lagi kalau masih terlihat & belum ada
  /// controller.
  void _onSlotFree() {
    if (!mounted) return;
    if (_visibleFraction >= 0.6 && _controller == null && !_acquiring) {
      unawaited(_ensureAndPlay());
    }
  }

  void _addSlotListener() {
    if (_slotListenerRegistered) return;
    _slotListenerRegistered = true;
    _registry.addSlotFreeListener(_onSlotFree);
  }

  void _removeSlotListener() {
    if (!_slotListenerRegistered) return;
    _slotListenerRegistered = false;
    _registry.removeSlotFreeListener(_onSlotFree);
  }

  // ─── Render ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo = controller != null && controller.value.isInitialized;
    final playing = showVideo && controller.value.isPlaying;

    return VisibilityDetector(
      key: ValueKey(widget.videoUrl),
      onVisibilityChanged: _onVisibilityChanged,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // DASAR: foto selalu ada — identik layer foto existing.
            _buildPhoto(context),
            // Video fade-in di atas foto (foto→video halus, tak pernah flash
            // hitam karena foto tetap di bawah).
            AnimatedOpacity(
              opacity: showVideo ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: showVideo
                  ? _buildVideoCover(controller)
                  : const SizedBox.shrink(),
            ),
            // Chip subtle pojok kiri-bawah saat video main.
            if (playing)
              const Positioned(left: 6, bottom: 6, child: _PlayingChip()),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoto(BuildContext context) {
    final url = widget.imageUrl?.trim() ?? '';
    if (url.isEmpty) return _PhotoFallback(color: _gridSurfaceTint(context));
    return CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => _PhotoFallback(color: _gridSurfaceTint(context)),
      errorWidget: (_, __, ___) =>
          _PhotoFallback(color: _gridSurfaceTint(context)),
    );
  }

  /// Render cover video tanpa distorsi (pola feed): FittedBox cover pakai
  /// ukuran asli video, jadi video portrait tidak gepeng di kotak 1:1.
  Widget _buildVideoCover(VideoPlayerController controller) {
    final size = controller.value.size;
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ],
    );
  }
}

/// Warna dasar/placeholder foto grid — cocokkan tint grid Beranda.
Color _gridSurfaceTint(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? cs.surfaceContainerLow
      : const Color(0xFFEEF1F5);
}

class _PhotoFallback extends StatelessWidget {
  final Color color;
  const _PhotoFallback({required this.color});

  @override
  Widget build(BuildContext context) => ColoredBox(color: color);
}

/// Chip subtle penanda video sedang main — gaya sama badge counter existing,
/// sengaja tidak mencolok (soft, kapsul hitam transparan).
class _PlayingChip extends StatelessWidget {
  const _PlayingChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.videocam_rounded, size: 12, color: Colors.white),
      ),
    );
  }
}
