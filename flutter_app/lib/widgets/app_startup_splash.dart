import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppStartupSplash extends StatefulWidget {
  final Widget child;

  const AppStartupSplash({
    super.key,
    required this.child,
  });

  @override
  State<AppStartupSplash> createState() => _AppStartupSplashState();
}

class _AppStartupSplashState extends State<AppStartupSplash> {
  static const _minimumVisibleDuration = Duration(milliseconds: 1400);
  static const _fadeDuration = Duration(milliseconds: 360);

  bool _visible = true;
  bool _mountedOverlay = true;
  Timer? _hideTimer;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    _hideTimer = Timer(_minimumVisibleDuration, () {
      if (!mounted) return;
      setState(() => _visible = false);
      _removeTimer = Timer(_fadeDuration, () {
        if (mounted) setState(() => _mountedOverlay = false);
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_mountedOverlay)
          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: _fadeDuration,
            curve: Curves.easeOutCubic,
            child: const _StartupSplashSurface(),
          ),
      ],
    );
  }
}

class _StartupSplashSurface extends StatelessWidget {
  const _StartupSplashSurface();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF0A0F1A) : const Color(0xFF1E5FBF);
    final logoAsset = isDark
        ? 'assets/native/splash-logo-dark.png'
        : 'assets/native/splash-logo.png';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: background,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.96, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Image.asset(
                    logoAsset,
                    width: 118,
                    height: 118,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
