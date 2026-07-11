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

/// Slide #1 galeri detail produk: video **autoplay bisu visible-only**
/// (pola Tokopedia + grid Beranda `ProductGridVideo`).
///
/// Saat slide cukup terlihat (>=0.6) video otomatis main **bisu** (`setVolume(0)`,
/// `_muted=true` default) — tombol 🔇/🔊 di pojok kanan-bawah (bareng ⛶) untuk
/// unmute. Poster (thumbnail→foto produk→hitam) render **contain di latar hitam**
/// sama seperti video main, jadi tak ada "pop" cover→contain saat init selesai.
/// Tap area video = toggle play/pause (ikon ⏸/▶ sekejap). ⛶ buka viewer
/// fullscreen (bersuara) — karena inline bisu, tak ada double-audio.
///
/// Lifecycle penting (hero ada di dalam scroll view + PageView):
/// - `VisibilityDetector`: TRANSISI ke terlihat (>=0.6) → ensure controller +
///   play (bisu); TRANSISI ke tak-terlihat (<0.5) → `pauseIfPlaying()`. Dipicu
///   di transisi (bukan tiap event) supaya pause manual saat diam tidak
///   ditimpa.
/// - App background (`WidgetsBindingObserver.paused`) → pause. Autoplay resume
///   saat slide terlihat lagi.
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

  /// Dipanggil saat user tap tombol ⛶ (pojok kanan-bawah video). Task 4
  /// men-supply callback ini (push viewer fullscreen). Sebelum callback
  /// dipanggil, state ini sudah `pauseIfPlaying()` (lihat `_openFullscreen`)
  /// supaya suara tidak dobel saat viewer fullscreen mulai main.
  final VoidCallback? onOpenFullscreen;

  const ProductDetailVideoSlide({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    this.posterImageUrl,
    this.durationSec,
    this.onOpenFullscreen,
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

  /// Apakah slide sedang cukup terlihat (>=0.6). Ini konsep "should be playing":
  /// autoplay hanya saat `_visible`. Dipakai sebagai gate di `_ensureAndPlay`
  /// (menggantikan `_playIntent` lama): kalau slide sudah scroll-off selama
  /// `initialize()` in-flight, JANGAN `play()` controller yang tak terlihat.
  /// Init inline bisu, jadi tak ada isu double-audio dengan viewer fullscreen.
  bool _visible = false;

  /// Bisu default (`true` → `setVolume(0)`). Tombol 🔇/🔊 men-toggle-nya +
  /// `_controller?.setVolume(_muted ? 0 : 1)`.
  bool _muted = true;

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
      // App ke background → pause. Autoplay bisu resume nanti lewat transisi
      // visibility saat slide terlihat lagi.
      pauseIfPlaying();
    }
  }

  // ─── Public API (dipanggil parent Task 6 + visibility/lifecycle) ──────────

  /// Pause kalau ada controller yang sedang main. Idempotent & aman dipanggil
  /// kapan saja (init in-flight / belum init / sudah pause → no-op).
  /// TIDAK menandai "jangan autoplay lagi": begitu slide terlihat lagi, transisi
  /// visibility memanggil `_ensureAndPlay` → resume (bisu).
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

  /// Pastikan ada controller yang init & main (bisu). Lazy + race-guarded.
  /// Dipanggil saat TRANSISI ke terlihat (VisibilityDetector) — bukan tap.
  /// Kalau controller sudah ada, cukup resume (mis. balik dari pause off-screen).
  Future<void> _ensureAndPlay() async {
    final existing = _controller;
    if (existing != null) {
      if (existing.value.isInitialized && !existing.value.isPlaying) {
        unawaited(existing.play());
        if (mounted) setState(() {});
      }
      return;
    }
    if (_initializing) return; // init sedang jalan — jangan bikin dua.
    final url = widget.videoUrl.trim();
    if (url.isEmpty) return;

    // Default options (bukan mixWithOthers): dibisukan via `setVolume(0)`, jadi
    // playback bisu tak mengganggu musik latar user tanpa perlu mixWithOthers.
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
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || !identical(_controller, controller)) {
        _initializing = false;
        unawaited(controller.dispose());
        return;
      }
      controller.addListener(_onControllerTick);
      // Slide sudah scroll-off selama init (`_visible=false` lewat transisi
      // visibility<0.5)? JANGAN `play()` video yang tak terlihat — biarkan
      // paused (frame-1, resumable saat terlihat lagi / via `_togglePlay`).
      // Reset `_initializing` supaya UI keluar dari loading.
      if (!_visible) {
        setState(() => _initializing = false);
        return;
      }
      await controller.play();
      if (!mounted || !identical(_controller, controller)) {
        _initializing = false;
        controller.removeListener(_onControllerTick);
        unawaited(controller.dispose());
        return;
      }
      // Jadi tak-terlihat SELAMA `await play()` (yield point) → pause segera.
      // Controller tetap initialized-tapi-paused (resumable), JANGAN dispose.
      if (!_visible) {
        unawaited(controller.pause());
        setState(() => _initializing = false);
        return;
      }
      setState(() => _initializing = false);
    } catch (_) {
      // Init gagal (URL rusak / hiccup) → balik ke poster (retry saat terlihat
      // lagi), JANGAN kotak hitam.
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

  /// Handler tombol ⛶: pause inline dulu (hemat decoder + hentikan playback
  /// yang tak terlihat saat viewer fullscreen naik), baru serahkan ke Task 4
  /// lewat callback parent. Inline bisu jadi tak ada isu double-audio.
  void _openFullscreen() {
    pauseIfPlaying();
    widget.onOpenFullscreen?.call();
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

  /// Toggle bisu/bersuara (tombol 🔇/🔊). Ubah `_muted` + volume controller
  /// (aman kalau controller null / belum init — `setVolume` disimpan & dipakai
  /// saat init selesai lewat `setVolume(_muted ? 0 : 1)` di `_ensureAndPlay`).
  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
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
        // Dipicu di TRANSISI (bukan tiap event) supaya pause manual saat diam
        // tidak ditimpa. Terlihat (>=0.6) → autoplay bisu; tak-terlihat (<0.5)
        // → pause. Hysteresis 0.5..0.6 = pertahankan state (anti flicker).
        if (info.visibleFraction >= 0.6 && !_visible) {
          _visible = true;
          unawaited(_ensureAndPlay());
        } else if (info.visibleFraction < 0.5 && _visible) {
          _visible = false;
          pauseIfPlaying();
        }
      },
      child: ColoredBox(
        color: Colors.black,
        child: playing
            ? _buildPlaying(controller)
            : _buildThumbnail(context),
      ),
    );
  }

  // Overlay poster saat init/belum-terlihat: poster contain + kapsul + kontrol
  // (mute + ⛶). Autoplay bisu jalan begitu terlihat, jadi poster cuma sekejap.
  Widget _buildThumbnail(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPoster(),
        if (_initializing)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        // Kapsul kiri-atas "Video".
        const Positioned(top: 12, left: 12, child: _Capsule(text: 'Video')),
        // Kapsul kanan-atas durasi mm:ss (sembunyi kalau durationSec null).
        if (widget.durationSec != null)
          Positioned(
            top: 12,
            right: 12,
            child: _Capsule(text: _formatDuration(widget.durationSec!)),
          ),
        // Kontrol pojok kanan-bawah [🔇][⛶] — child TERAKHIR (topmost).
        _BottomRightControls(
          muted: _muted,
          onToggleMute: _toggleMute,
          onOpenFullscreen: _openFullscreen,
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
      // CONTAIN (bukan cover): samakan dengan render video yang contain-di-hitam,
      // jadi tak ada "pop" ukuran cover→contain saat autoplay mulai.
      fit: BoxFit.contain,
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
      fit: BoxFit.contain,
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
          // Kontrol [🔇][⛶] pojok kanan-bawah — child TERAKHIR (topmost) di
          // Stack ini, yang jadi child dari GestureDetector luar (_togglePlay).
          // Karena topmost, hit-test-nya duluan ketemu & memenangkan gesture
          // arena duluan → tap kontrol TIDAK jatuh ke _togglePlay (lihat dok
          // _BottomRightControls). Posisi bottom:12 aman dari progress bar
          // (tinggi ~9px, padding top 5 + LinearProgressIndicator 4).
          _BottomRightControls(
            muted: _muted,
            onToggleMute: _toggleMute,
            onOpenFullscreen: _openFullscreen,
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

/// Kontrol pojok kanan-bawah video: [🔇/🔊 mute][⛶ fullscreen] (pola Tokopedia,
/// mute + fullscreen berdampingan). Dua kapsul gaya `_Capsule` (black 0.55 /
/// radius 999), ikon putih 20.
///
/// `GestureDetector` tiap tombol DISENGAJA terpisah dari `GestureDetector`
/// play/pause di `_buildPlaying` — bukan `onTap` tunggal yang bercabang. Widget
/// ini HARUS jadi child TERAKHIR di `Stack` pemanggilnya (poster & playing):
/// Stack hit-test anak dari topmost (child terakhir) ke bawah, jadi tap di area
/// kontrol kena widget ini duluan & menang di gesture arena (recognizer yang
/// duluan masuk arena menang saat sweep) — tap TIDAK jatuh ke GestureDetector
/// toggle play/pause di baliknya.
class _BottomRightControls extends StatelessWidget {
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenFullscreen;
  const _BottomRightControls({
    required this.muted,
    required this.onToggleMute,
    required this.onOpenFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CapsuleIconButton(
            icon: muted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            onTap: onToggleMute,
          ),
          const SizedBox(width: 8),
          _CapsuleIconButton(
            icon: Icons.fullscreen_rounded,
            onTap: onOpenFullscreen,
          ),
        ],
      ),
    );
  }
}

/// Kapsul tombol ikon (black 0.55 / radius 999 / ikon putih 20) — dipakai
/// tombol mute & fullscreen di `_BottomRightControls`.
class _CapsuleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CapsuleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
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
