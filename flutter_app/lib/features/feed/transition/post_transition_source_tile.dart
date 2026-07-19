import 'package:flutter/widgets.dart';

import 'post_detail_transition_session.dart';

@immutable
class PostTransitionTileId {
  const PostTransitionTileId({required this.scope, required this.postId});

  final String scope;
  final String postId;

  @override
  bool operator ==(Object other) =>
      other is PostTransitionTileId &&
      other.scope == scope &&
      other.postId == postId;

  @override
  int get hashCode => Object.hash(scope, postId);
}

class PostTransitionTileRegistry {
  final Map<PostTransitionTileId, _PostTransitionSourceTileState> _tiles = {};
  int _layoutGeneration = 0;

  int get layoutGeneration => _layoutGeneration;

  void markLayoutChanged() => _layoutGeneration++;

  PostPageSourceTarget? resolve(PostTransitionTileId id) =>
      _tiles[id]?._snapshot();

  void setSuppressed(PostTransitionTileId id, bool suppressed) {
    _tiles[id]?._setSuppressed(suppressed);
  }

  void _attach(PostTransitionTileId id, _PostTransitionSourceTileState state) {
    _tiles[id] = state;
  }

  void _detach(PostTransitionTileId id, _PostTransitionSourceTileState state) {
    if (identical(_tiles[id], state)) _tiles.remove(id);
  }
}

class PostTransitionSourceTile extends StatefulWidget {
  const PostTransitionSourceTile({
    super.key,
    required this.registry,
    required this.id,
    required this.fallbackColor,
    required this.child,
    this.imageProvider,
  });

  final PostTransitionTileRegistry registry;
  final PostTransitionTileId id;
  final Color fallbackColor;
  final ImageProvider<Object>? imageProvider;
  final Widget child;

  @override
  State<PostTransitionSourceTile> createState() =>
      _PostTransitionSourceTileState();
}

class _PostTransitionSourceTileState extends State<PostTransitionSourceTile> {
  late final ImageStreamListener _imageListener;
  ImageStream? _imageStream;
  ImageInfo? _resolvedImage;
  bool _suppressed = false;

  @override
  void initState() {
    super.initState();
    _imageListener = ImageStreamListener(_handleImageFrame);
    widget.registry._attach(widget.id, this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageProvider();
  }

  @override
  void didUpdateWidget(PostTransitionSourceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry || oldWidget.id != widget.id) {
      oldWidget.registry._detach(oldWidget.id, this);
      _suppressed = false;
      widget.registry._attach(widget.id, this);
    }
    if (oldWidget.imageProvider != widget.imageProvider) {
      _resolveImageProvider();
    }
  }

  void _resolveImageProvider() {
    final provider = widget.imageProvider;
    if (provider == null) {
      _replaceImageStream(null);
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == stream.key) return;
    _replaceImageStream(stream);
  }

  void _replaceImageStream(ImageStream? stream) {
    _imageStream?.removeListener(_imageListener);
    _imageStream = stream;
    final oldImage = _resolvedImage;
    _resolvedImage = null;
    oldImage?.dispose();
    stream?.addListener(_imageListener);
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    final retainedImage = imageInfo.clone();
    imageInfo.dispose();
    final oldImage = _resolvedImage;
    _resolvedImage = retainedImage;
    oldImage?.dispose();
  }

  PostPageSourceTarget? _snapshot() {
    final tileRenderObject = context.findRenderObject();
    final overlayRenderObject = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (tileRenderObject is! RenderBox ||
        overlayRenderObject is! RenderBox ||
        !tileRenderObject.attached ||
        !overlayRenderObject.attached ||
        !tileRenderObject.hasSize ||
        !overlayRenderObject.hasSize) {
      return null;
    }
    final rect =
        tileRenderObject.localToGlobal(
          Offset.zero,
          ancestor: overlayRenderObject,
        ) &
        tileRenderObject.size;
    return PostPageSourceTarget(
      postId: widget.id.postId,
      rect: rect,
      proxy: PostPageMediaProxy(
        placeholderColor: widget.fallbackColor,
        imageInfo: _resolvedImage,
      ),
      viewportSize: overlayRenderObject.size,
      textDirection: Directionality.of(context),
      layoutGeneration: widget.registry.layoutGeneration,
    );
  }

  void _setSuppressed(bool suppressed) {
    if (!mounted || _suppressed == suppressed) return;
    setState(() => _suppressed = suppressed);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: _suppressed,
        child: Opacity(
          key: ValueKey('post-transition-tile-opacity-${widget.id.postId}'),
          opacity: _suppressed ? 0 : 1,
          child: widget.child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.registry._detach(widget.id, this);
    _imageStream?.removeListener(_imageListener);
    _resolvedImage?.dispose();
    _resolvedImage = null;
    super.dispose();
  }
}
