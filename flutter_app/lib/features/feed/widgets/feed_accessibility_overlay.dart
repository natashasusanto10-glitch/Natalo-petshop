import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

/// Visual cue for videos that intentionally have no audio track.
///
/// This is informational, not a button, so assistive technologies do not
/// announce a mute action that cannot do anything.
class FeedNoAudioIndicator extends StatelessWidget {
  const FeedNoAudioIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Video tanpa suara',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.volume_off_rounded, color: Colors.white, size: 15),
                SizedBox(width: 5),
                Text(
                  'Tanpa suara',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

/// Loads and displays a WebVTT file without taking ownership of [controller].
///
/// Subtitle failures are deliberately silent: media playback remains the
/// primary experience even when a subtitle URL expires or contains bad data.
class FeedWebVttSubtitleOverlay extends StatefulWidget {
  const FeedWebVttSubtitleOverlay({
    super.key,
    required this.controller,
    required this.subtitleUrl,
    this.visible = true,
  });

  final VideoPlayerController controller;
  final String? subtitleUrl;
  final bool visible;

  @override
  State<FeedWebVttSubtitleOverlay> createState() =>
      _FeedWebVttSubtitleOverlayState();
}

class _FeedWebVttSubtitleOverlayState extends State<FeedWebVttSubtitleOverlay> {
  static const int _maxSubtitleBytes = 256 * 1024;

  List<Caption> _captions = const [];
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCaptions());
  }

  @override
  void didUpdateWidget(covariant FeedWebVttSubtitleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitleUrl != widget.subtitleUrl) {
      unawaited(_loadCaptions());
    }
  }

  Future<void> _loadCaptions() async {
    final revision = ++_loadRevision;
    final rawUrl = widget.subtitleUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      if (mounted) setState(() => _captions = const []);
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      if (mounted) setState(() => _captions = const []);
      return;
    }

    if (mounted && _captions.isNotEmpty) {
      setState(() => _captions = const []);
    }

    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > _maxSubtitleBytes) return;

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > _maxSubtitleBytes) return;
        bytes.addAll(chunk);
      }
      final parsed = WebVTTCaptionFile(utf8.decode(bytes)).captions;
      if (!mounted || revision != _loadRevision) return;
      setState(() => _captions = List<Caption>.unmodifiable(parsed));
    } catch (_) {
      // Subtitle metadata is optional. Never interrupt or replace playback.
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || _captions.isEmpty) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final text = feedSubtitleTextAt(_captions, value.position);
        if (text == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: ExcludeSemantics(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

@visibleForTesting
String? feedSubtitleTextAt(List<Caption> captions, Duration position) {
  var low = 0;
  var high = captions.length - 1;
  while (low <= high) {
    final middle = low + ((high - low) ~/ 2);
    final caption = captions[middle];
    if (position < caption.start) {
      high = middle - 1;
    } else if (position > caption.end) {
      low = middle + 1;
    } else {
      final text = caption.text.trim();
      return text.isEmpty ? null : text;
    }
  }
  return null;
}
