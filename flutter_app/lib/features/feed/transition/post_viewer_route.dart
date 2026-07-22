import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Route standar untuk semua alur grid→viewer post. Model IG/TikTok:
/// halaman viewer TIDAK PERNAH menggeser horizontal — ia MENUTUP LAYAR PENUH
/// (opaque) dengan transisi FADE, sementara media terbang tile↔slot lewat
/// [PostHero] di overlay framework (dua arah: push DAN pop, tanpa gating).
/// Dismiss vertikal (drag-down) disediakan oleh viewer sendiri (maybePop).
///
/// TAMBAHAN: gestur swipe-horizontal dari TEPI KIRI untuk menutup (back).
/// Ini adalah port setia dari mesin back-gesture Cupertino milik Flutter SDK
/// (`packages/flutter/lib/src/cupertino/route.dart`), TAPI transisi tetap FADE.
/// Gestur hanya menggerakkan [controller] route (nilai 1.0→0.0 saat digeser
/// kanan): fade memudarkan halaman DAN — karena [PostHero] memakai
/// `transitionOnUserGestures: true` — hero terbang balik ke tile, sekaligus
/// membuka grid di bawahnya (route memang mengecat rute di bawah saat transisi).
/// Berlaku di iOS DAN Android (ini gestur kita sendiri, bukan bawaan platform).
/// TANPA slide horizontal konten halaman.
class PostViewerRoute<T> extends PageRoute<T> {
  PostViewerRoute({required this.builder, super.settings});

  /// Membangun konten utama viewer.
  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  // WAJIB opaque: begitu terbuka, viewer menutupi grid sepenuhnya —
  // TIDAK ada tap-through ke tile di bawahnya (regresi lama).
  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Transisi TETAP fade — tidak berubah. Detector gestur selalu membungkus
    // child (ia sendiri hanya aktif saat pop-gesture diizinkan), meniru pola
    // Cupertino. Yang digerakkan gestur hanyalah [controller] route ini.
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: _PostViewerBackGestureDetector<T>(
        enabledCallback: () => _isPopGestureEnabled(this),
        onStartPopGesture: () => _startPopGesture<T>(this),
        child: child,
      ),
    );
  }

  /// Apakah ada gestur pop yang sedang berlangsung untuk route ini.
  ///
  /// Cermin [_CupertinoBackGestureController]: gestur men-set
  /// `navigator.didStartUserGesture()`/`didStopUserGesture()`, jadi status ini
  /// terbaca lewat `navigator.userGestureInProgress`.
  @override
  bool get popGestureInProgress => navigator!.userGestureInProgress;

  /// Apakah gestur pop bisa dimulai user untuk route ini.
  ///
  /// Cermin `_isPopGestureEnabled` Cupertino.
  static bool _isPopGestureEnabled<T>(PostViewerRoute<T> route) {
    // Kalau tak ada tujuan untuk kembali, jelas gestur tak didukung.
    if (route.isFirst) {
      return false;
    }
    // Kalau pop akan ditangani internal (mis. nested navigator), gestur akan
    // membingungkan — larang.
    if (route.willHandlePopInternally) {
      return false;
    }
    // Kalau pop route ini mungkin diveto (mis. PopScope canPop=false),
    // jangan izinkan geser-tutup.
    if (route.popDisposition == RoutePopDisposition.doNotPop) {
      return false;
    }
    // Fullscreen dialog memakai transisi bawah-atas, bukan geser-tepi.
    if (route.fullscreenDialog) {
      return false;
    }
    // Kalau sedang beranimasi (push/pop belum selesai), tak bisa digeser manual.
    if (route.animation!.status != AnimationStatus.completed) {
      return false;
    }
    if (route.controller!.isAnimating) {
      return false;
    }
    // Kalau sudah ada gestur pop berjalan, jangan mulai yang baru.
    if (route.popGestureInProgress) {
      return false;
    }
    // Sepertinya gestur back disambut baik!
    return true;
  }

  // Dipanggil oleh [_PostViewerBackGestureDetector] saat gestur drag "back"
  // dimulai. Controller yang dikembalikan menangani semua event drag berikutnya.
  // Akses `controller` (protected di TransitionRoute) dilakukan DARI DALAM kelas
  // route, lalu diteruskan ke gesture controller.
  static _PostViewerBackGestureController<T> _startPopGesture<T>(
    PostViewerRoute<T> route,
  ) {
    assert(_isPopGestureEnabled(route));
    return _PostViewerBackGestureController<T>(
      navigator: route.navigator!,
      controller: route.controller!, // akses protected
      getIsCurrent: () => route.isCurrent,
      getIsActive: () => route.isActive,
    );
  }
}

Future<T?> pushPostViewer<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  return Navigator.of(context).push<T>(PostViewerRoute<T>(builder: builder));
}

const double _kBackGestureWidth = 20.0;
const double _kMinFlingVelocity = 1.0; // Lebar layar per detik.

// Durasi animasi saat halaman dilepas di tengah swipe.
const Duration _kDroppedSwipePageAnimationDuration =
    Duration(milliseconds: 350);

/// Sisi-widget dari [_PostViewerBackGestureController].
///
/// Port setia dari `_CupertinoBackGestureDetector`: menyediakan gesture
/// recognizer horizontal yang, saat menentukan route bisa ditutup dengan gestur
/// back, membuat controller dan menyuapinya input dari recognizer. Area sentuh
/// dibatasi ke ~20px tepi kiri (`_kBackGestureWidth`).
class _PostViewerBackGestureDetector<T> extends StatefulWidget {
  const _PostViewerBackGestureDetector({
    super.key,
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final Widget child;

  final ValueGetter<bool> enabledCallback;

  final ValueGetter<_PostViewerBackGestureController<T>> onStartPopGesture;

  @override
  _PostViewerBackGestureDetectorState<T> createState() =>
      _PostViewerBackGestureDetectorState<T>();
}

class _PostViewerBackGestureDetectorState<T>
    extends State<_PostViewerBackGestureDetector<T>> {
  _PostViewerBackGestureController<T>? _backGestureController;

  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();

    // Kalau di-dispose saat drag berlangsung, panggil didStopUserGesture.
    if (_backGestureController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_backGestureController?.navigator.mounted ?? false) {
          _backGestureController?.navigator.didStopUserGesture();
        }
        _backGestureController = null;
      });
    }
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    assert(mounted);
    assert(_backGestureController == null);
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    assert(mounted);
    assert(_backGestureController != null);
    _backGestureController!.dragUpdate(
      _convertToLogical(details.primaryDelta! / context.size!.width),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    assert(mounted);
    assert(_backGestureController != null);
    _backGestureController!.dragEnd(
      _convertToLogical(
          details.velocity.pixelsPerSecond.dx / context.size!.width),
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    assert(mounted);
    // Bisa terpanggil walau start tak dipanggil, berpasangan dengan event
    // "down" yang tak kita pedulikan di sini.
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
  }

  double _convertToLogical(double value) {
    return switch (Directionality.of(context)) {
      TextDirection.rtl => -value,
      TextDirection.ltr => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    // Untuk perangkat dengan notch, area drag perlu lebih lebar di sisi notch.
    final double dragAreaWidth = switch (Directionality.of(context)) {
      TextDirection.rtl => MediaQuery.paddingOf(context).right,
      TextDirection.ltr => MediaQuery.paddingOf(context).left,
    };
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        PositionedDirectional(
          start: 0.0,
          width: max(dragAreaWidth, _kBackGestureWidth),
          top: 0.0,
          bottom: 0.0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

/// Controller untuk gestur back ala iOS.
///
/// Port setia dari `_CupertinoBackGestureController`. Dibuat oleh
/// [PostViewerRoute] merespons gestur yang ditangkap
/// [_PostViewerBackGestureDetector], lalu diberi input olehnya. Ia mengendalikan
/// [AnimationController] milik route.
///
/// Bekerja sepenuhnya dalam koordinat logis (0.0 = halaman baru tertutup,
/// 1.0 = halaman baru di atas).
class _PostViewerBackGestureController<T> {
  _PostViewerBackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsActive,
    required this.getIsCurrent,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsActive;
  final ValueGetter<bool> getIsCurrent;

  /// Gestur drag berubah sebesar [delta]. Rentang total drag 0.0..1.0.
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  /// Gestur drag berakhir dengan [velocity] horizontal sebagai fraksi lebar
  /// layar per detik.
  void dragEnd(double velocity) {
    // Fling ke arah yang sesuai.
    const Curve animationCurve = Curves.fastEaseInToSlowEaseOut;
    final bool isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      // Kalau halaman sudah dinavigasi menjauh, arah animasi bergantung apakah
      // ia masih di stack, terlepas dari velocity/posisi drag.
      animateForward = getIsActive();
    } else if (velocity.abs() >= _kMinFlingVelocity) {
      // Kalau dilepas sebelum mid-screen dengan velocity cukup, atau setelah
      // mid-screen, animasikan halaman keluar. Selain itu, kembalikan.
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      controller.animateTo(
        1.0,
        duration: _kDroppedSwipePageAnimationDuration,
        curve: animationCurve,
      );
    } else {
      if (isCurrent) {
        // Route ini ditakdirkan pop di titik ini. Gunakan ulang pop navigator.
        navigator.pop();
      }

      // Pop bisa selesai inline kalau sudah di tujuan.
      if (controller.isAnimating) {
        controller.animateBack(
          0.0,
          duration: _kDroppedSwipePageAnimationDuration,
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      // Pertahankan userGestureInProgress true agar kurva transisi tak berubah
      // di tengah terbang.
      late AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
