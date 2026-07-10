import 'package:flutter/material.dart';

/// Scrim gradient bawah feed (330px, transparent → black .24 → black .76,
/// stops [0, .54, 1]) — memastikan keterbacaan caption/kreator/produk di
/// atas video/foto.
///
/// Ekstraksi 1:1 dari feed_screen (dulu blok `DecoratedBox` inline di
/// `_FeedPostViewState.build`). Positioned + IgnorePointer tetap di
/// pemanggil; widget ini murni bagian gradient-nya saja.
class FeedPostScrim extends StatelessWidget {
  final double height;

  const FeedPostScrim({super.key, this.height = 330});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.24),
              Colors.black.withValues(alpha: 0.76),
            ],
            stops: const [0, 0.54, 1],
          ),
        ),
      ),
    );
  }
}
