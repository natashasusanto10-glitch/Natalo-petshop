import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';

class AppLottieAsset extends StatelessWidget {
  final String asset;
  final double size;
  final bool repeat;

  const AppLottieAsset({
    super.key,
    required this.asset,
    this.size = 116,
    this.repeat = true,
  });

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      asset,
      height: size,
      width: size,
      repeat: repeat,
      fit: BoxFit.contain,
      frameRate: FrameRate.max,
    );
  }
}

class AppLoadingState extends StatelessWidget {
  final String label;

  const AppLoadingState({
    super.key,
    this.label = 'Memuat data...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLottieAsset(
              asset: 'assets/lottie/loading_paw.json',
              size: 112,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final String title;
  final String body;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const AppEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLottieAsset(
              asset: 'assets/lottie/empty_box.json',
              size: 132,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                height: 1.42,
              ),
            ),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onPressed,
                child: Text(buttonLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppSuccessMark extends StatelessWidget {
  final double size;

  const AppSuccessMark({super.key, this.size = 94});

  @override
  Widget build(BuildContext context) {
    return AppLottieAsset(
      asset: 'assets/lottie/success_check.json',
      size: size,
      repeat: false,
    );
  }
}
