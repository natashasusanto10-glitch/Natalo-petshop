import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

// Mirror of components/feed/BlurhashCanvas.tsx (Wave 2).
//
// Decode blurhash string → 32×32 raster → scale to container size via Flutter
// painting. Decode is ~1-3ms, <4 KB memory per instance. Falls back to solid
// black if hash is null/invalid (no error).

class BlurhashCanvas extends StatelessWidget {
  final String? hash;
  final BoxFit fit;

  const BlurhashCanvas({
    super.key,
    required this.hash,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (hash == null || hash!.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return BlurHash(
      hash: hash!,
      imageFit: fit,
      decodingWidth: 32,
      decodingHeight: 32,
      color: Colors.black,
    );
  }
}
