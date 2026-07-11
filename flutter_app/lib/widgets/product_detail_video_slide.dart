import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../theme/natalo_colors.dart';

/// Brand blue lokal — samakan dengan `_brandBlue` di product_detail_screen.dart
/// (di sana `NataloColors.primary`, yang identik dengan `NataloColors.nataloBlue`
/// = 0xFF1E5FBF). Dipakai untuk `VideoProgressIndicator.playedColor`.
const _brandBlue = NataloColors.nataloBlue;

/// Slide #1 galeri detail produk: video **manual-play** (bersuara).
///
/// Beda dengan grid Beranda (`ProductGridVideo`, autoplay bisu visible-only):
/// video detail TIDAK autoplay — user harus tap ▶ (keputusan user, boleh
/// duck musik latar). Sebelum play tampil thumbnail + overlay premium (kapsul
/// "Video" + durasi mm:ss, tombol ▶), saat main render **contain di latar
/// hitam** (letterbox — konsisten foto detail yang `BoxFit.contain`).
///
/// Lifecycle penting (hero ada di dalam scroll view + PageView):
/// - `VisibilityDetector` < 0.5 → `pauseIfPlaying()` (suara tidak lanjut saat
///   user scroll ke deskripsi).
/// - App background (`WidgetsBindingObserver.paused`) → pause. TIDAK auto-resume
///   (play detail = keputusan user).
/// - Parent (`_ProductHero`, Task 6) pegang `GlobalKey<ProductDetailVideoSlideState>`
///   dan panggil [ProductDetailVideoSlideState.pauseIfPlaying] saat user swipe ke
///   slide lain — makanya State class ini **publik** (private tak bisa direferensi
///   lintas-file).
class ProductDetailVideoSlide extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  /// Poster fallback saat `thumbnailUrl` null/kosong/gagal — biasanya
  /// `product.imageUrl` (produk selalu punya foto). Tanpa ini, produk yang
  /// punya video tapi thumbnail-nya null/error tampil slide hitam + ▶ saja.
  final String? posterImageUrl;
  final int? durationSec;

  const ProductDetailVideoSlide({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    this.posterImageUrl,
    this.durationSec,
  });

  @override
  ProductDetailVideoSlideState createState() => ProductDetailVideoSlideState();
}

/// PUBLIK (bukan `_ProductDetailVideoSlideState`) supaya Task 6 di file
/// `product_detail_screen.dart` bisa `GlobalKey<ProductDetailVideoSlideState>()`
/// lalu `.currentState?.pauseIfPlaying()`.
class ProductDetailVideoSlideState extends State<ProductDetailVideoSlide>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// True selama `initialize()` + setup in-flight (ada `await` belum selesai).
  /// Dipakai untuk: (a) render loading (bukan playing walau controller sudah
  /// ada), (b) cegah re-entry, (c) single-ownership dispose — saat in-flight,
  /// `dispose()` TIDAK men-dispose controller; race guard di `_startPlayback`
  /// yang dispose (cegah double-dispose).
  bool _initializing = false;

  /// Guard supaya teardown finish/error tidak terjadwal dua kali.
  bool _tearingDown = false;

  /// Ikon toggle play/pause yang muncul sekejap lalu fade saat user tap.
  bool _showToggleIcon = false;
  Timer? _toggleIconTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toggleIconTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      // Kalau init MASIH in-flight: JANGAN dispose di sini — race guard di
      // `_startPlayback` (`!mounted`/`!identical`) yang akan dispose. Dispose
      // ganda controller = assertion "already disposed".
      if (!_initializing) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // App ke background → pause. TIDAK auto-resume saat `resumed`
      // (play detail = keputusan user, jangan mendadak bersuara).
      pauseIfPlaying();
    }
  }

  // ─── Public API (dipanggil parent Task 6 + visibility/lifecycle) ──────────

  /// Pause kalau ada controller yang sedang main. Idempotent & aman dipanggil
  /// kapan saja (init in-flight / belum init / sudah pause → no-op).
  void pauseIfPlaying() {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying) {
      unawaited(controller.pause());
      if (mounted) setState(() {}); // munculkan overlay ▶ (paused).
    }
  }

  // ─── Playback ─────────────────────────────────────────────────────────────

  Future<void> _startPlayback() async {
    if (_initializing || _controller != null) return; // cegah double.
    final url = widget.videoUrl.trim();
    if (url.isEmpty) return;

    // Default options (bukan mixWithOthers): dipicu user & bersuara, boleh
    // duck musik latar.
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    setState(() => _initializing = true);
    try {
      await controller.initialize();
      // Race guard SETELAH await: widget lepas / `_controller` sudah di-swap →
      // buang controller lokal, jangan sentuh state lagi. Reset `_initializing`
      // juga supaya flag tak nyangkut di path apa pun (defensif).
      if (!mounted || !identical(_controller, controller)) {
        _initializing = false;
        unawaited(controller.dispose());
        return;
      }
      await controller.setLooping(false);
      if (!mounted || !identical(_controller, controller)) {
        _initializing = false;
        unawaited(controller.dispose());
        return;
      }
      controller.addListener(_onControllerTick);
      await controller.play();
      if (!mounted || !identical(_controller, controller)) {
        _initializing = false;
        controller.removeListener(_onControllerTick);
        unawaited(controller.dispose());
        return;
      }
      setState(() => _initializing = false);
    } catch (_) {
      // Init gagal (URL rusak / hiccup) → balik ke thumbnail + ▶ (retry),
      // JANGAN kotak hitam.
      controller.removeListener(_onControllerTick);
      if (identical(_controller, controller)) _controller = null;
      unawaited(controller.dispose());
      if (mounted) setState(() => _initializing = false);
    }
  }

  /// Listener controller: deteksi (a) error runtime & (b) video selesai →
  /// balik ke overlay thumbnail + ▶ (replay dari awal), BUKAN frame beku.
  /// Teardown ditunda via microtask supaya tidak dispose controller di
  /// tengah `notifyListeners`-nya sendiri (reentrancy hazard).
  void _onControllerTick() {
    final controller = _controller;
    if (controller == null || _tearingDown) return;
    final v = controller.value;
    final finished = v.isInitialized &&
        !v.isLooping &&
        v.duration > Duration.zero &&
        v.position >= v.duration;
    if (v.hasError || finished) {
      _tearingDown = true;
      scheduleMicrotask(_resetToThumbnail);
    }
  }

  /// Dispose controller & balik ke state thumbnail (dipanggil setelah finish/
  /// error, di luar loop notify).
  void _resetToThumbnail() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      unawaited(controller.pause());
      unawaited(controller.dispose());
    }
    _toggleIconTimer?.cancel();
    if (mounted) {
      setState(() {
        _initializing = false;
        _showToggleIcon = false;
        _tearingDown = false;
      });
    } else {
      _tearingDown = false;
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final willPlay = !controller.value.isPlaying;
    unawaited(willPlay ? controller.play() : controller.pause());
    _toggleIconTimer?.cancel();
    setState(() => _showToggleIcon = true);
    // Ikon nongol sekejap lalu fade (kalau lagi main). Saat pause overlay ▶
    // tetap terlihat karena build memaksa ikon saat `!isPlaying`.
    _toggleIconTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showToggleIcon = false);
    });
  }

  // ─── Render ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final playing = controller != null &&
        controller.value.isInitialized &&
        !_initializing;
    return VisibilityDetector(
      key: ValueKey('detail-video-${widget.videoUrl}'),
      onVisibilityChanged: (info) {
        // Hero ada di scroll view: scroll ke deskripsi → suara berhenti.
        if (info.visibleFraction < 0.5) pauseIfPlaying();
      },
      child: ColoredBox(
        color: Colors.black,
        child: playing
            ? _buildPlaying(controller)
            : _buildThumbnail(context),
      ),
    );
  }

  // Overlay sebelum play: poster + kapsul + tombol ▶ (atau loading).
  Widget _buildThumbnail(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPoster(),
        if (_initializing)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else
          Center(
            child: GestureDetector(
              // onTap SAJA — tidak makan horizontal drag (PageView swipe jalan).
              onTap: _startPlayback,
              child: const _CircleGlyph(icon: Icons.play_arrow_rounded),
            ),
          ),
        // Kapsul kiri-atas "Video".
        const Positioned(top: 12, left: 12, child: _Capsule(text: 'Video')),
        // Kapsul kanan-atas durasi mm:ss (sembunyi kalau durationSec null).
        if (widget.durationSec != null)
          Positioned(
            top: 12,
            right: 12,
            child: _Capsule(text: _formatDuration(widget.durationSec!)),
          ),
      ],
    );
  }

  Widget _buildPoster() {
    // Prioritas: thumbnailUrl → posterImageUrl (foto produk) → hitam netral.
    // Produk selalu punya foto, jadi thumbnail null/error TIDAK boleh jadi
    // slide hitam; jatuh ke posterImageUrl dulu. ▶ + kapsul tetap di atas.
    final thumb = widget.thumbnailUrl?.trim() ?? '';
    final poster = widget.posterImageUrl?.trim() ?? '';
    if (thumb.isEmpty) return _posterImage(poster); // langsung ke fallback foto.
    return CachedNetworkImage(
      imageUrl: thumb,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => _posterImage(poster),
      errorWidget: (_, __, ___) => _posterImage(poster),
    );
  }

  /// Fallback poster: foto produk kalau ada, kalau tidak hitam netral.
  Widget _posterImage(String posterUrl) {
    if (posterUrl.isEmpty) return const ColoredBox(color: Colors.black);
    return CachedNetworkImage(
      imageUrl: posterUrl,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Colors.black),
      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }

  // Saat main: contain di latar hitam (pola feed) — foto detail juga contain,
  // jadi video letterbox, tidak gepeng.
  Widget _buildPlaying(VideoPlayerController controller) {
    final size = controller.value.size;
    final isPlaying = controller.value.isPlaying;
    // Ikon nampak saat: baru toggle (fade) ATAU sedang pause (affordance resume).
    final showIcon = _showToggleIcon || !isPlaying;
    return GestureDetector(
      // onTap SAJA + opaque: tap di area hitam letterbox pun ke-detect, tapi
      // horizontal drag TIDAK di-claim → PageView tetap bisa swipe.
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          Center(
            child: AnimatedOpacity(
              opacity: showIcon ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _CircleGlyph(
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: _brandBlue),
            ),
          ),
        ],
      ),
    );
  }
}

/// m:ss dari detik (0:05, 1:09, 12:00) — SELARAS web `ProductImageCarousel.
/// formatClock` (menit TIDAK di-pad, detik di-pad 2). Klamp negatif ke 0.
String _formatDuration(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final m = s ~/ 60;
  final sec = s % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// Lingkaran 64 hitam-transparan + ikon putih 36. Dipakai tombol ▶ (thumbnail)
/// & ikon toggle (playing) — konsisten satu gaya.
class _CircleGlyph extends StatelessWidget {
  final IconData icon;
  const _CircleGlyph({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 36),
    );
  }
}

/// Kapsul badge — gaya PERSIS counter `x/y` existing (product_detail_screen.dart
/// ~829-846): black 0.55 / radius 999 / teks putih 11 w800. Bukan gaya baru.
class _Capsule extends StatelessWidget {
  final String text;
  const _Capsule({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
