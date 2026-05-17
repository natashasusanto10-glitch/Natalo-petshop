import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/bunny_upload.dart' show bunnyHlsToMp4, rewriteBunnyMp4Quality;
import '../models/feed_post.dart';
import '../services/network_tier.dart';
import '../state/feed_provider.dart';
import 'blurhash_canvas.dart';

// Mirror of components/feed/FeedVideoPlayer.tsx (Wave 1 quality picker +
// Wave 2 HLS adaptive + Wave 4 cinema mode).
//
// Key behaviors:
//   - Blurhash placeholder visible until first frame ready (Wave 2 LQIP)
//   - HLS on WiFi (player.adaptive auto-switch), MP4 on cellular at
//     network-tier recommended quality (Wave 1)
//   - Loop, mute by default (tap to unmute), autoplay when active
//   - Cinema mode: tap top-right button → enterFullScreen() (Wave 4).
//     better_player_plus's fullscreen uses native AVPlayer/ExoPlayer chrome,
//     so we get scrubbing, AirPlay, PIP, rotation for free — no NSE hack
//     equivalent needed.

class FeedVideoPlayer extends ConsumerStatefulWidget {
  final FeedPost post;
  final bool isActive;
  final VoidCallback? onDoubleTap;

  const FeedVideoPlayer({
    super.key,
    required this.post,
    required this.isActive,
    this.onDoubleTap,
  });

  @override
  ConsumerState<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends ConsumerState<FeedVideoPlayer> {
  BetterPlayerController? _controller;
  bool _firstFrameReady = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  @override
  void didUpdateWidget(FeedVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.post.id != widget.post.id) {
      _disposeController();
      _firstFrameReady = false;
      _setupController();
    } else if (old.isActive != widget.isActive) {
      _syncPlayState();
    }
  }

  void _setupController() {
    if (!widget.post.hasVideo) return;

    final netInfo =
        ref.read(networkTierServiceProvider).current;
    final url = _resolvePlaybackUrl(widget.post, netInfo);

    final dataSource = BetterPlayerDataSource(
      _isHls(url)
          ? BetterPlayerDataSourceType.network
          : BetterPlayerDataSourceType.network,
      url,
      videoFormat: _isHls(url) ? BetterPlayerVideoFormat.hls : null,
      cacheConfiguration: const BetterPlayerCacheConfiguration(useCache: false),
    );

    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: widget.isActive,
        looping: true,
        aspectRatio: _aspectRatio(widget.post),
        fit: BoxFit.contain, // letterbox vertical (9:16) on wider screens
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false, // we render our own engagement overlay
        ),
        eventListener: (event) {
          if (event.betterPlayerEventType ==
              BetterPlayerEventType.initialized) {
            if (mounted) {
              setState(() => _firstFrameReady = true);
              _controller?.setVolume(_muted ? 0 : 1);
            }
          }
        },
      ),
      betterPlayerDataSource: dataSource,
    );
  }

  void _syncPlayState() {
    final c = _controller;
    if (c == null) return;
    if (widget.isActive) {
      c.play();
    } else {
      c.pause();
      c.seekTo(Duration.zero);
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  String _resolvePlaybackUrl(FeedPost post, NetworkInfo net) {
    final original = post.videoUrl!;
    if (shouldUseHls(net)) {
      // Wave 2: prefer HLS on WiFi
      return original.endsWith('.m3u8')
          ? original
          : original.replaceFirst(RegExp(r'/play_\d+p\.mp4$'), '/playlist.m3u8');
    }
    // Wave 1: cellular → MP4 at recommended quality
    final q = recommendedVideoQuality(net);
    return original.endsWith('.m3u8')
        ? bunnyHlsToMp4(original, q)
        : rewriteBunnyMp4Quality(original, q);
  }

  bool _isHls(String url) => url.endsWith('.m3u8');

  double _aspectRatio(FeedPost post) {
    final w = post.videoWidth, h = post.videoHeight;
    if (w != null && h != null && w > 0 && h > 0) return w / h;
    return 9 / 16; // default vertical
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _enterCinemaMode() async {
    // Wave 4 — native fullscreen via better_player_plus.
    // On iOS this maps to AVPlayerViewController, on Android to PlayerActivity.
    _controller?.enterFullScreen();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: widget.onDoubleTap,
      onTap: _toggleMute,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurhash placeholder — visible until first frame ready (Wave 2)
          if (!_firstFrameReady)
            BlurhashCanvas(hash: widget.post.thumbnailBlurhash),

          if (_controller != null)
            AnimatedOpacity(
              opacity: _firstFrameReady ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: BetterPlayer(controller: _controller!),
            ),

          // Top-right cinema mode + mute toggle
          Positioned(
            top: 16,
            right: 12,
            child: Column(
              children: [
                _IconChip(
                  icon: _muted ? Icons.volume_off : Icons.volume_up,
                  onTap: _toggleMute,
                ),
                const SizedBox(height: 8),
                _IconChip(
                  // Wave 4: cinema mode (native fullscreen)
                  icon: Icons.fullscreen,
                  onTap: _enterCinemaMode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconChip({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
