import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'photo_crop_transform.dart';

/// Optional overlay di atas image, di dalam clip frame yang sama. Dipakai
/// profile picker untuk gambar mask lingkaran (area luar lingkaran diredupkan).
/// [frameSize] = ukuran frame crop (bukan ukuran image). Return null = tak ada
/// overlay (default feed picker).
typedef PhotoCropOverlayBuilder = Widget? Function(
  BuildContext context,
  Size frameSize,
);

// ─── Pure crop math (unit-testable, no widget deps) ───────────────────

/// Batas offset piksel (setengah selisih ukuran image ter-scale vs frame) —
/// di luar ini image tidak menutupi frame lagi. Return (maxDx, maxDy) ≥ 0.
Offset cropMaxOffsetPx(Size frame, Size base, double scale) {
  final maxDx = math.max(0.0, (base.width * scale - frame.width) / 2);
  final maxDy = math.max(0.0, (base.height * scale - frame.height) / 2);
  return Offset(maxDx, maxDy);
}

/// Resistensi rubber-band ala iOS `UIScrollView`: makin jauh di-tarik makin
/// berat. [overshoot] = jarak melewati batas (px, ≥0), [dim] = dimensi frame
/// pada sumbu itu. Konstanta [c] = 0.55 (nilai iOS yang dikenal luas).
double rubberBand(double overshoot, double dim, {double c = 0.55}) {
  if (overshoot <= 0 || dim <= 0) return 0;
  return (overshoot * dim * c) / (dim + c * overshoot);
}

/// Clamp offset dengan rubber-band: dalam batas → apa adanya; di luar batas →
/// batas + resistensi (bukan hard stop).
Offset applyRubberClamp(Offset raw, Offset maxOff, Size frame,
    {double c = 0.55}) {
  double axis(double v, double max, double dim) {
    if (v > max) return max + rubberBand(v - max, dim, c: c);
    if (v < -max) return -max - rubberBand(-max - v, dim, c: c);
    return v;
  }

  return Offset(
    axis(raw.dx, maxOff.dx, frame.width),
    axis(raw.dy, maxOff.dy, frame.height),
  );
}

/// Zoom "tentang sebuah titik": jaga titik image di bawah [focal] tetap diam
/// saat scale berubah dengan rasio [ratio]. [offset] & [focal] dalam koordinat
/// relatif pusat frame. Inilah yang bikin pinch nempel ke jari (bukan zoom ke
/// tengah frame).
Offset zoomAboutPoint(Offset offset, Offset focal, double ratio) {
  return focal - (focal - offset) * ratio;
}

// ─── Widget ───────────────────────────────────────────────────────────

/// Preview crop pan/zoom Instagram-style. Dipakai bersama feed media picker
/// (aspect 4:5) dan profile photo picker (aspect 1:1 + mask lingkaran via
/// [overlayBuilder]).
///
/// Engine gesture pakai raw [Listener] (BUKAN [GestureDetector]) supaya
/// multi-touch terdeteksi dari frame pertama tanpa rebutan gesture-arena
/// melawan scroll view di atasnya — dulu cubitan awal sering "hilang". Fitur:
/// focal-point zoom (nempel jari), momentum fling saat lepas, rubber-band di
/// tepi. Double-tap reset lewat [GestureDetector] berlapis (recognizer
/// double-tap cuma nyala saat double-tap sungguhan, tak mencuri drag).
class PhotoCropPreview extends StatefulWidget {
  final File file;
  final bool fitOriginal;
  final PhotoCropTransform cropTransform;

  /// Optional pre-loaded image dimensions dari parent. Kalau di-set, widget
  /// skip internal load (instant interactive). Kalau null, fallback ke
  /// internal load via ui.instantiateImageCodec (fast).
  final Size? preloadedImageSize;

  /// Optional overlay (mis. mask lingkaran) di atas image dalam clip frame.
  final PhotoCropOverlayBuilder? overlayBuilder;

  const PhotoCropPreview({
    super.key,
    required this.file,
    required this.fitOriginal,
    required this.cropTransform,
    this.preloadedImageSize,
    this.overlayBuilder,
  });

  @override
  State<PhotoCropPreview> createState() => _PhotoCropPreviewState();
}

class _PhotoCropPreviewState extends State<PhotoCropPreview>
    with TickerProviderStateMixin {
  Size? _imageSize;

  // Live gesture state (px, relatif pusat frame).
  final Map<int, Offset> _pointers = {};
  Offset _activeOffsetPx = Offset.zero;
  double _activeScale = 1;
  Offset _prevCentroid = Offset.zero;
  double _prevSpan = 0;

  // Velocity estimate (px/s) untuk fling.
  Offset _velocity = Offset.zero;
  int _lastMoveMicros = 0;

  // Double-tap manual (kita pakai Listener + EagerGestureRecognizer, jadi
  // tak bisa numpang GestureDetector.onDoubleTap — recognizer double-tap
  // takkan pernah menang arena karena Eager sudah klaim pointer).
  int _gestureStartMicros = 0;
  double _moveAccum = 0;
  int _maxPointersThisGesture = 0;
  int _lastTapMicros = 0;
  Offset _lastTapPos = Offset.zero;
  static const int _doubleTapWindowMicros = 300000;
  static const double _tapSlop = 12; // px gerak maks agar dianggap tap
  static const double _doubleTapSlop = 40; // jarak antar dua tap

  // Frame/base dihitung di build, dibaca handler pointer.
  Size _frameSize = Size.zero;
  Size _baseSize = Size.zero;

  late final Ticker _physicsTicker = createTicker(_onPhysicsTick);
  Duration _lastTick = Duration.zero;

  late final AnimationController _resetCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Offset _resetFromOffset = Offset.zero;
  double _resetFromScale = 1;

  // Physics constants — dinamai untuk device-tuning saat verify.
  // Crop foto profil butuh presisi (bukan scroll), jadi momentum SENGAJA
  // kalem: fling di-redam kuat supaya lepas jari tidak "meluncur kencang".
  static const double _flingGain = 0.3; // skala v saat lepas (0 = mati total)
  static const double _flingRetentionPerSec = 0.04; // fraksi v tersisa/detik
  static const double _settleRetentionPerSec = 0.0006; // ease balik ke batas
  static const double _minStopVelocity = 40; // px/s — berhenti lebih cepat
  static const double _maxTrackedVelocity = 2500; // px/s clamp

  @override
  void initState() {
    super.initState();
    if (widget.preloadedImageSize != null) {
      _imageSize = widget.preloadedImageSize;
    } else {
      _loadImageSize();
    }
    _syncFromTransform();
    _resetCtrl.addListener(_onResetTick);
  }

  @override
  void didUpdateWidget(covariant PhotoCropPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _imageSize = widget.preloadedImageSize;
      if (_imageSize == null) _loadImageSize();
      _stopMotion();
      _syncFromTransform();
    } else if (oldWidget.preloadedImageSize != widget.preloadedImageSize &&
        widget.preloadedImageSize != null) {
      _imageSize = widget.preloadedImageSize;
    }
  }

  @override
  void dispose() {
    _physicsTicker.dispose();
    _resetCtrl.dispose();
    super.dispose();
  }

  void _syncFromTransform() {
    _activeScale = widget.cropTransform.scale.clamp(1.0, 4.0).toDouble();
    // offsetFraction → px pakai frame terakhir (0 saat belum layout — akan
    // dikoreksi di move pertama karena kita re-derive dari fraction × frame).
    if (_frameSize.width > 0) {
      _activeOffsetPx = Offset(
        widget.cropTransform.offsetFraction.dx * _frameSize.width,
        widget.cropTransform.offsetFraction.dy * _frameSize.height,
      );
    }
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      if (!mounted) return;
      setState(() => _imageSize = size);
    } catch (_) {
      if (!mounted) return;
      setState(() => _imageSize = null);
    }
  }

  // ─── Pointer helpers ────────────────────────────────────────────────

  Offset _centroidCenterRel() {
    if (_pointers.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final p in _pointers.values) {
      sum += p;
    }
    final c = sum / _pointers.length.toDouble();
    return c - Offset(_frameSize.width / 2, _frameSize.height / 2);
  }

  double _span() {
    if (_pointers.length < 2) return 0;
    final pts = _pointers.values.toList();
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        sum += (pts[i] - pts[j]).distance;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  void _pushTransform() {
    if (_frameSize.width <= 0 || _frameSize.height <= 0) return;
    widget.cropTransform.update(
      scale: _activeScale,
      offsetFraction: Offset(
        _activeOffsetPx.dx / _frameSize.width,
        _activeOffsetPx.dy / _frameSize.height,
      ),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    final freshGesture = _pointers.isEmpty;
    _stopMotion();
    if (freshGesture) {
      _syncFromTransform();
      _gestureStartMicros = e.timeStamp.inMicroseconds;
      _moveAccum = 0;
      _maxPointersThisGesture = 0;
    }
    _pointers[e.pointer] = e.localPosition;
    _maxPointersThisGesture =
        math.max(_maxPointersThisGesture, _pointers.length);
    _prevCentroid = _centroidCenterRel();
    _prevSpan = _span();
    _velocity = Offset.zero;
    _lastMoveMicros = e.timeStamp.inMicroseconds;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final newCentroid = _centroidCenterRel();
    final newSpan = _span();

    // Pan: geser offset mengikuti pergerakan centroid 1:1.
    final panDelta = newCentroid - _prevCentroid;
    _activeOffsetPx += panDelta;
    _moveAccum += panDelta.distance;

    // Zoom fokus di titik jari (bukan tengah frame).
    if (_pointers.length >= 2 && _prevSpan > 0 && newSpan > 0) {
      final rawScale = _activeScale * (newSpan / _prevSpan);
      final nextScale = rawScale.clamp(1.0, 4.0).toDouble();
      final ratio = nextScale / _activeScale;
      _activeOffsetPx = zoomAboutPoint(_activeOffsetPx, newCentroid, ratio);
      _activeScale = nextScale;
    }

    // Rubber-band clamp (biar tak lari jauh, tapi tetap bisa over-drag halus).
    final maxOff = cropMaxOffsetPx(_frameSize, _baseSize, _activeScale);
    _activeOffsetPx = applyRubberClamp(_activeOffsetPx, maxOff, _frameSize);

    // Velocity untuk fling (px/s), di-smooth + di-clamp.
    final micros = e.timeStamp.inMicroseconds;
    final dt = (micros - _lastMoveMicros) / 1e6;
    if (dt > 0) {
      final inst = panDelta / dt;
      _velocity = _velocity * 0.4 + inst * 0.6;
      final mag = _velocity.distance;
      if (mag > _maxTrackedVelocity) {
        _velocity = _velocity * (_maxTrackedVelocity / mag);
      }
    }
    _lastMoveMicros = micros;

    _prevCentroid = newCentroid;
    _prevSpan = newSpan;
    _pushTransform();
  }

  void _onPointerUpOrCancel(
    int pointerId,
    Offset localPos,
    int micros, {
    required bool canceled,
  }) {
    _pointers.remove(pointerId);
    if (_pointers.isNotEmpty) {
      // Re-baseline supaya lepas satu jari tak bikin lompat.
      _prevCentroid = _centroidCenterRel();
      _prevSpan = _span();
      _velocity = Offset.zero;
      return;
    }

    // Gesture selesai (semua jari lepas). Deteksi double-tap dulu.
    final wasTap = !canceled &&
        _maxPointersThisGesture == 1 &&
        _moveAccum < _tapSlop &&
        (micros - _gestureStartMicros) < _doubleTapWindowMicros;
    if (wasTap) {
      final isDouble = (micros - _lastTapMicros) < _doubleTapWindowMicros &&
          (localPos - _lastTapPos).distance < _doubleTapSlop;
      if (isDouble) {
        _lastTapMicros = 0;
        _animateReset();
        return;
      }
      _lastTapMicros = micros;
      _lastTapPos = localPos;
    }
    // Redam energi fling saat lepas — crop butuh presisi, bukan glide jauh.
    _velocity = _velocity * _flingGain;
    _startSettle();
  }

  // ─── Physics: fling + rubber-band spring-back ───────────────────────

  void _startSettle() {
    final maxOff = cropMaxOffsetPx(_frameSize, _baseSize, _activeScale);
    final within = _activeOffsetPx.dx.abs() <= maxOff.dx + 0.5 &&
        _activeOffsetPx.dy.abs() <= maxOff.dy + 0.5;
    // Kalau diam di dalam batas, tak perlu animasi.
    if (within && _velocity.distance < _minStopVelocity) {
      _snapWithinBounds(maxOff);
      return;
    }
    _lastTick = Duration.zero;
    if (!_physicsTicker.isActive) _physicsTicker.start();
  }

  void _onPhysicsTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    final maxOff = cropMaxOffsetPx(_frameSize, _baseSize, _activeScale);

    // Friction fling.
    _velocity = _velocity * math.pow(_flingRetentionPerSec, dt).toDouble();
    var next = _activeOffsetPx + _velocity * dt;

    // Per-sumbu rubber settle: kalau di luar batas, ease balik + redam v.
    next = Offset(
      _settleAxis(next.dx, maxOff.dx, dt, isX: true),
      _settleAxis(next.dy, maxOff.dy, dt, isX: false),
    );
    _activeOffsetPx = next;
    _pushTransform();

    final within = _activeOffsetPx.dx.abs() <= maxOff.dx + 0.5 &&
        _activeOffsetPx.dy.abs() <= maxOff.dy + 0.5;
    if (_velocity.distance < _minStopVelocity && within) {
      _snapWithinBounds(maxOff);
      _physicsTicker.stop();
    }
  }

  double _settleAxis(double value, double max, double dt, {required bool isX}) {
    if (value > max || value < -max) {
      final target = value > max ? max : -max;
      final k = 1 - math.pow(_settleRetentionPerSec, dt).toDouble();
      final eased = value + (target - value) * k;
      // Redam velocity sumbu ini.
      _velocity = isX
          ? Offset(_velocity.dx * 0.6, _velocity.dy)
          : Offset(_velocity.dx, _velocity.dy * 0.6);
      return eased;
    }
    return value;
  }

  void _snapWithinBounds(Offset maxOff) {
    _activeOffsetPx = Offset(
      _activeOffsetPx.dx.clamp(-maxOff.dx, maxOff.dx),
      _activeOffsetPx.dy.clamp(-maxOff.dy, maxOff.dy),
    );
    _velocity = Offset.zero;
    _pushTransform();
  }

  void _stopMotion() {
    if (_physicsTicker.isActive) _physicsTicker.stop();
    if (_resetCtrl.isAnimating) _resetCtrl.stop();
  }

  // ─── Double-tap reset (animated) ────────────────────────────────────

  void _animateReset() {
    _stopMotion();
    _resetFromOffset = _activeOffsetPx;
    _resetFromScale = _activeScale;
    _resetCtrl
      ..reset()
      ..forward();
  }

  void _onResetTick() {
    final t = Curves.easeOutCubic.transform(_resetCtrl.value);
    _activeScale = _resetFromScale + (1 - _resetFromScale) * t;
    _activeOffsetPx = _resetFromOffset * (1 - t);
    _pushTransform();
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frameSize = Size(constraints.maxWidth, constraints.maxHeight);
          _frameSize = frameSize;

          if (widget.fitOriginal) {
            return Image.file(
              widget.file,
              fit: BoxFit.contain,
              alignment: Alignment.center,
            );
          }

          final imageSize = _imageSize;
          if (imageSize == null ||
              frameSize.width <= 0 ||
              frameSize.height <= 0) {
            return Image.file(
              widget.file,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            );
          }

          final coverScale = math.max(
            frameSize.width / imageSize.width,
            frameSize.height / imageSize.height,
          );
          final baseSize = Size(
            imageSize.width * coverScale,
            imageSize.height * coverScale,
          );
          _baseSize = baseSize;

          final dpr = MediaQuery.devicePixelRatioOf(context);
          final targetDecodeWidth =
              (frameSize.width * 4 * dpr).clamp(512.0, 1920.0).toInt();

          return RepaintBoundary(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: (e) =>
                  _onPointerUpOrCancel(e.pointer, e.localPosition,
                      e.timeStamp.inMicroseconds, canceled: false),
              onPointerCancel: (e) => _onPointerUpOrCancel(
                  e.pointer, e.localPosition, e.timeStamp.inMicroseconds,
                  canceled: true),
              // EagerGestureRecognizer klaim arena di area preview supaya
              // scroll view di atasnya TIDAK ikut bereaksi saat user
              // pan/pinch crop (kalau tidak, drag vertikal akan meng-crop
              // sekaligus meng-collapse header — dobel). Listener tetap baca
              // raw pointer untuk gesture; recognizer ini cuma pemenang arena.
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
                },
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ListenableBuilder(
                        listenable: widget.cropTransform,
                        builder: (context, _) {
                          final scale = widget.cropTransform.scale
                              .clamp(1.0, 4.0)
                              .toDouble();
                          final offsetPx = Offset(
                            widget.cropTransform.offsetFraction.dx *
                                frameSize.width,
                            widget.cropTransform.offsetFraction.dy *
                                frameSize.height,
                          );
                          final matrix = Matrix4.identity()
                            ..translateByDouble(offsetPx.dx, offsetPx.dy, 0, 1)
                            ..scaleByDouble(scale, scale, 1, 1);
                          return Center(
                            child: Transform(
                              transform: matrix,
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: baseSize.width,
                                height: baseSize.height,
                                child: Image.file(
                                  widget.file,
                                  fit: BoxFit.fill,
                                  alignment: Alignment.center,
                                  // Cuma cacheWidth (bukan +cacheHeight manual)
                                  // — decoder pakai aspect asli file utk
                                  // hitung tinggi sendiri, jadi tak mungkin
                                  // meleset dari _imageSize kita dan bikin
                                  // gambar ter-squish saat BoxFit.fill.
                                  cacheWidth: targetDecodeWidth,
                                  filterQuality: FilterQuality.low,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (widget.overlayBuilder != null)
                        widget.overlayBuilder!(context, frameSize) ??
                            const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
