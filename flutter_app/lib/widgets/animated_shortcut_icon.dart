import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../utils/motion_prefs.dart';

enum ShortcutArtwork {
  catFood('cat-food', Icons.pets_rounded),
  dogFood('dog-food', Icons.cookie_rounded),
  fishFood('fish-food', Icons.set_meal_rounded),
  medicine('medicine', Icons.medication_rounded),
  promo('promo', Icons.local_fire_department_rounded),
  newProducts('new-products', Icons.auto_awesome_rounded),
  voucher('voucher', Icons.confirmation_number_rounded),
  points('points', Icons.redeem_rounded);

  const ShortcutArtwork(this.fileName, this.fallback);
  final String fileName;
  final IconData fallback;
  String get asset => 'assets/lottie/shortcuts/$fileName.json';

  // Meaningful stills: avoid voucher's invisible entry and points' transition.
  double get stillProgress => switch (this) {
        ShortcutArtwork.newProducts => .74,
        ShortcutArtwork.voucher => .72,
        ShortcutArtwork.points => 0,
        _ => 0,
      };
}

/// All visible shortcuts loop together. Animation pauses when the app/route or
/// shortcut leaves view, and honors both the app and OS motion preferences.
class AnimatedShortcutIcon extends StatefulWidget {
  const AnimatedShortcutIcon(
      {super.key, required this.artwork, this.size = 72});

  final ShortcutArtwork artwork;
  final double size;

  @override
  State<AnimatedShortcutIcon> createState() => _AnimatedShortcutIconState();
}

class _AnimatedShortcutIconState extends State<AnimatedShortcutIcon>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(vsync: this);
  final _visibilityKey = UniqueKey();
  bool _visible = true;
  bool _foreground = true;
  bool _reduce = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    motionPrefs.addListener(_preferencesChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MotionPrefs.shouldReduce(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedShortcutIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artwork != widget.artwork) {
      _controller.stop();
      _controller.duration = null;
      _controller.value = widget.artwork.stillProgress;
    }
  }

  void _preferencesChanged() {
    _reduce = MotionPrefs.shouldReduce(context);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted || _controller.duration == null) return;
    if (_reduce) {
      _controller.stop();
      _controller.value = widget.artwork.stillProgress;
    } else if (_visible && _foreground && _tickerEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    motionPrefs.removeListener(_preferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: VisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: (info) {
          _visible = info.visibleFraction > 0;
          _sync();
        },
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: Lottie.asset(
              widget.artwork.asset,
              key: ValueKey(widget.artwork),
              controller: _controller,
              fit: BoxFit.contain,
              frameRate: FrameRate.composition,
              onLoaded: (composition) {
                if (!mounted) return;
                _controller.duration = composition.duration;
                _sync();
              },
              errorBuilder: (context, error, stackTrace) {
                FlutterError.reportError(FlutterErrorDetails(
                  exception: error,
                  stack: stackTrace,
                  library: 'Natalo shortcut artwork',
                  context: ErrorDescription('loading ${widget.artwork.asset}'),
                ));
                return Icon(widget.artwork.fallback, size: widget.size * .55);
              },
            ),
          ),
        ),
      ),
    );
  }
}
