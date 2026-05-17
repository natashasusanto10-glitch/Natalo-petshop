import 'package:flutter/material.dart';

import '../widgets/app_product_image.dart';

/// Fullscreen image viewer dengan pinch-to-zoom — dipakai dari product detail
/// gallery saat user tap thumbnail. Minimal: PageView + InteractiveViewer.
class ImageViewerScreen extends StatelessWidget {
  /// Pakai salah satu — multi-page `images` ATAU single `url`.
  final List<String>? images;
  final String? url;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    this.images,
    this.url,
    this.initialIndex = 0,
  }) : assert(images != null || url != null,
            'ImageViewerScreen butuh images atau url');

  List<String> get _list => images ?? [url!];

  @override
  Widget build(BuildContext context) {
    final controller = PageController(initialPage: initialIndex);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: _list.length,
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: AppProductImage(imageUrl: _list[i])),
        ),
      ),
    );
  }
}
