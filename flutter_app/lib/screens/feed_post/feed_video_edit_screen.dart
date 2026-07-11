import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/feed_create_post_draft.dart';
import '../../services/app_analytics.dart';
import '../../state/settings_store.dart';
import '../../utils/haptics.dart';
import '../../utils/video_frame_thumbs.dart';
import '../../widgets/app_toast.dart';
import '../feed_new_post_screen.dart';
import 'feed_cover_picker_screen.dart';

const _editBg = Color(0xFF05070D);
const _editBlue = Color(0xFF1E5BFF);
const _editCard = Color(0xFF11141B);
const _editBorder = Color(0xFF252A35);
const _editText = Color(0xFFFFFFFF);
const _editMuted = Color(0xFFAEB7C7);

const _minEditVideoSeconds = 1;
const _maxEditVideoSeconds = 60;
const _editFrameCount = 10;

/// Layar edit video fullscreen tunggal — gabungan Preview + Trim lama
/// (Fase 2B). Video full-bleed edge-to-edge (tanpa radius/padding
/// horizontal); timeline trim muncul otomatis untuk video >60s, atau via
/// toggle "Potong" untuk video <=60s. Suara ikut `appSettingsStore.feedMuted`
/// (bukan hardcode mute). Sampul bisa dipilih in-editor via
/// `FeedCoverPickerScreen`. Next instan — TIDAK mengkompres di layar ini;
/// kompresi terjadi di `FeedUploadStore` (Approach B).
class FeedVideoEditScreen extends StatefulWidget {
  final FeedCreatePostDraft draft;

  const FeedVideoEditScreen({super.key, required this.draft});

  @override
  State<FeedVideoEditScreen> createState() => _FeedVideoEditScreenState();
}

class _FeedVideoEditScreenState extends State<FeedVideoEditScreen> {
  VideoPlayerController? _controller;
  RangeValues _range = RangeValues(0, _maxEditVideoSeconds.toDouble());
  bool _loading = true;
  bool _playing = false;
  String? _error;
  Timer? _playbackGuard;
  Timer? _timecodeTicker;
  int _lastShownPosSec = -1;
  late bool _showTimeline;

  // Frame thumbnails untuk timeline trim, IG-style.
  List<Uint8List?> _frameThumbs = const [];

  // Sampul in-editor.
  String? _pickedCoverPath;
  RangeValues? _coverPickedAtRange;

  Duration get _duration => widget.draft.originalDuration ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(AppAnalytics.logEvent('feed_post_edit_opened'));
    // Pakai milliseconds (bukan inSeconds yang truncate) — klip 60.5s
    // harus tetap dianggap >60s dan wajib trim, bukan lolos jadi <=60s
    // karena pembulatan ke bawah.
    _showTimeline = _duration.inMilliseconds > _maxEditVideoSeconds * 1000;
    _range = RangeValues(
      0,
      math.min(
        _maxEditVideoSeconds.toDouble(),
        math.max(1, _duration.inMilliseconds / 1000),
      ),
    );
    _initVideo();
    _timecodeTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized || !ctrl.value.isPlaying) {
        return;
      }
      final posSec = ctrl.value.position.inSeconds;
      if (posSec != _lastShownPosSec) {
        _lastShownPosSec = posSec;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _playbackGuard?.cancel();
    _timecodeTicker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final path = widget.draft.localVideoPath;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = 'Video belum bisa dipreview. Pilih video lain.';
      });
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
      controller.addListener(_syncPlaying);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller
          .seekTo(Duration(milliseconds: (_range.start * 1000).round()));
      await controller.play();
      _startPlaybackGuard();
      unawaited(_extractFrameThumbnails(path));
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Video belum bisa dipreview. Pilih video lain.';
      });
    }
  }

  Future<void> _extractFrameThumbnails(String videoPath) async {
    final durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) return;
    final frames = List<Uint8List?>.filled(_editFrameCount, null);
    await extractVideoFrameThumbs(
      videoPath: videoPath,
      startMs: 0,
      spanMs: durationMs,
      count: _editFrameCount,
      onFrame: (i, bytes) {
        if (!mounted) return;
        frames[i] = bytes;
        setState(() => _frameThumbs = List<Uint8List?>.from(frames));
      },
    );
  }

  void _syncPlaying() {
    final playing = _controller?.value.isPlaying ?? false;
    if (mounted && _playing != playing) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    AppHaptics.tap();
    if (controller.value.isPlaying) {
      _playbackGuard?.cancel();
      await controller.pause();
    } else {
      await controller.play();
      _startPlaybackGuard();
    }
  }

  void _startPlaybackGuard() {
    _playbackGuard?.cancel();
    _playbackGuard = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized || !ctrl.value.isPlaying) {
        return;
      }
      final posSec = ctrl.value.position.inMilliseconds / 1000;
      if (posSec >= _range.end) {
        ctrl.seekTo(Duration(milliseconds: (_range.start * 1000).round()));
      }
    });
  }

  void _updateRange(RangeValues values, {required bool dragging}) {
    final old = _range;
    final total = math.max(1.0, _duration.inMilliseconds / 1000);
    var start = values.start.clamp(0.0, total - 1);
    var end = values.end.clamp(start + 1, total);
    final movedStart =
        (values.start - old.start).abs() > (values.end - old.end).abs();

    if (end - start > _maxEditVideoSeconds) {
      if (movedStart) {
        end = math.min(total, start + _maxEditVideoSeconds);
      } else {
        start = math.max(0, end - _maxEditVideoSeconds);
      }
    }
    if (end - start < _minEditVideoSeconds) {
      if (movedStart) {
        start = math.max(0, end - _minEditVideoSeconds);
      } else {
        end = math.min(total, start + _minEditVideoSeconds);
      }
    }

    setState(() {
      _range = RangeValues(start.toDouble(), end.toDouble());
      // Sampul basi di luar rentang baru — buang + kasih tau user.
      if (_coverPickedAtRange != null && _coverPickedAtRange != _range) {
        _pickedCoverPath = null;
        _coverPickedAtRange = null;
        if (mounted) {
          AppToast.show(
            context,
            'Sampul direset karena rentang berubah',
            kind: ToastKind.info,
          );
        }
      }
    });

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final seekTo = movedStart ? start : end;
    controller.seekTo(Duration(milliseconds: (seekTo * 1000).round()));
    if (dragging) {
      controller.pause();
    } else {
      controller.seekTo(Duration(milliseconds: (start * 1000).round()));
      controller.play();
      _startPlaybackGuard();
    }
  }

  void _toggleTimeline() {
    // Video >60s wajib trim — tidak bisa disembunyikan.
    if (_duration.inSeconds > _maxEditVideoSeconds) return;
    AppHaptics.selection();
    setState(() => _showTimeline = !_showTimeline);
  }

  Future<void> _toggleSound() async {
    AppHaptics.selection();
    final nextMuted = !appSettingsStore.feedMuted;
    await appSettingsStore.setFeedMuted(nextMuted);
    await _controller?.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() {});
  }

  Future<void> _openCoverPicker() async {
    final path = widget.draft.localVideoPath;
    if (path == null) return;
    await _controller?.pause();
    if (!mounted) return;
    final rangeStart = Duration(milliseconds: (_range.start * 1000).round());
    final rangeSpan = Duration(
      milliseconds: ((_range.end - _range.start) * 1000).round(),
    );
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => FeedCoverPickerScreen(
          videoPath: path,
          rangeStart: rangeStart,
          rangeSpan: rangeSpan,
          currentCoverPath: _pickedCoverPath ?? widget.draft.thumbnailPath,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _pickedCoverPath = result;
        _coverPickedAtRange = _range;
      });
    }
  }

  /// Approach B: Next instan — TIDAK mengkompres di layar ini. Rentang
  /// pilihan disimpan ke draft (trimStart + trimmedDuration); kompresi
  /// terjadi SEKALI di FeedUploadStore saat upload dimulai.
  Future<void> _confirmSelection() async {
    final selectedSeconds = (_range.end - _range.start).round();
    if (selectedSeconds < _minEditVideoSeconds ||
        selectedSeconds > _maxEditVideoSeconds) {
      setState(() {
        _error = 'Pilih durasi antara 1 sampai 60 detik.';
      });
      return;
    }
    AppHaptics.tap();
    await _controller?.pause();
    if (!mounted) return;

    // Full-range hanya bila seleksi menutup durasi PENUH dalam
    // milliseconds — klip 60.5s dengan seleksi 60s BUKAN full range
    // (0.5s terpotong), jadi wajib masuk trimStart/trimmedDuration
    // supaya kompresi benar-benar memotong. inSeconds (truncate) di sini
    // sebelumnya bikin klip 60.x lolos dianggap "full" dan tidak di-trim.
    final isFullRange = _range.start == 0 &&
        selectedSeconds * 1000 >= _duration.inMilliseconds;
    var next = widget.draft;
    if (!isFullRange) {
      next = next.copyWith(
        trimStart: Duration(milliseconds: (_range.start * 1000).round()),
        trimmedDuration: Duration(seconds: selectedSeconds),
      );
    }
    if (_pickedCoverPath != null) {
      next = next.copyWith(thumbnailPath: _pickedCoverPath, userPickedCover: true);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.video(next),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = math.max(1.0, _duration.inMilliseconds / 1000);
    final selectedDuration = Duration(
      milliseconds: ((_range.end - _range.start) * 1000).round(),
    );
    final posMs = _controller?.value.position.inMilliseconds ??
        (_range.start * 1000).round();
    return Scaffold(
      backgroundColor: _editBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _EditVideoStage(
                    controller: _controller,
                    thumbnailPath: _pickedCoverPath ?? widget.draft.thumbnailPath,
                    loading: _loading,
                    playing: _playing,
                    onTap: _togglePlay,
                  ),
                  if (_error != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 100,
                      child: _EditErrorBox(message: _error!),
                    ),
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: SizedBox(
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Text(
                            'Edit Video',
                            style: TextStyle(
                              color: _editText,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 8),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _FrostedCircleButton(
                              icon: Icons.arrow_back_rounded,
                              onTap: () => Navigator.pop(context),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _SolidCircleButton(
                              icon: Icons.arrow_forward_rounded,
                              enabled: !_loading,
                              onTap: _loading ? null : _confirmSelection,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _FrostedPill(
                          child: Text(
                            '${_formatDuration(Duration(milliseconds: posMs))} / '
                            '${_formatDuration(_duration)}',
                            style: const TextStyle(
                              color: _editText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _FrostedPill(
                          onTap: _toggleSound,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                appSettingsStore.feedMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: _editText,
                                size: 16,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                appSettingsStore.feedMuted ? 'Senyap' : 'Suara',
                                style: const TextStyle(
                                  color: _editText,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${_formatDuration(selectedDuration)} dipilih',
                    style: const TextStyle(
                      color: _editText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Maksimal 60 detik',
                    style: TextStyle(
                      color: _editMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_showTimeline) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _EditTrimTimeline(
                  frameThumbs: _frameThumbs,
                  fallbackThumbnailPath: widget.draft.thumbnailPath,
                  range: _range,
                  totalSeconds: totalSeconds,
                  onChanged: (values, {required bool dragging}) =>
                      _updateRange(values, dragging: dragging),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Geser pegangan untuk memangkas video',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _editMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolbarPill(
                      icon: Icons.content_cut_rounded,
                      label: 'Potong',
                      onTap: _toggleTimeline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ToolbarPill(
                      icon: Icons.photo_rounded,
                      label: 'Sampul',
                      onTap: _openCoverPicker,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditVideoStage extends StatelessWidget {
  final VideoPlayerController? controller;
  final String? thumbnailPath;
  final bool loading;
  final bool playing;
  final VoidCallback? onTap;

  const _EditVideoStage({
    required this.controller,
    required this.thumbnailPath,
    required this.loading,
    required this.playing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnailPath != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Transform.scale(
                scale: 1.12,
                child: Image.file(File(thumbnailPath!), fit: BoxFit.cover),
              ),
            ),
          if (ctrl != null && ctrl.value.isInitialized)
            Center(
              child: FittedBox(
                fit: _isHorizontalSize(ctrl.value.size)
                    ? BoxFit.contain
                    : BoxFit.cover,
                child: SizedBox(
                  width: ctrl.value.size.width,
                  height: ctrl.value.size.height,
                  child: VideoPlayer(ctrl),
                ),
              ),
            )
          else if (thumbnailPath != null)
            Image.file(File(thumbnailPath!), fit: BoxFit.cover)
          else if (loading)
            const SizedBox.shrink()
          else
            const Center(
              child: Icon(
                Icons.videocam_off_rounded,
                color: Colors.white38,
                size: 48,
              ),
            ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: loading ? null : onTap,
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator(color: _editBlue)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isHorizontalSize(Size size) {
  if (size.width <= 0 || size.height <= 0) return false;
  return size.width > size.height;
}

class _FrostedCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FrostedCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _SolidCircleButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _SolidCircleButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? _editBlue : Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _FrostedPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _FrostedPill({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}

class _ToolbarPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _editText,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditErrorBox extends StatelessWidget {
  final String message;

  const _EditErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1821),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF7A7A)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFFFCDD2),
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Instagram-style trim timeline — copy adaptasi dari layar trim lama
/// (`feed_video_upload_flow.dart`), disengaja duplikat (no cross-import
/// antar file layar; layar lama masih hidup sampai Task 5).
typedef _EditTimelineDragCallback = void Function(
  RangeValues values, {
  required bool dragging,
});

class _EditTrimTimeline extends StatefulWidget {
  final List<Uint8List?> frameThumbs;
  final String? fallbackThumbnailPath;
  final RangeValues range;
  final double totalSeconds;
  final _EditTimelineDragCallback? onChanged;

  const _EditTrimTimeline({
    required this.frameThumbs,
    required this.fallbackThumbnailPath,
    required this.range,
    required this.totalSeconds,
    required this.onChanged,
  });

  @override
  State<_EditTrimTimeline> createState() => _EditTrimTimelineState();
}

class _EditTrimTimelineState extends State<_EditTrimTimeline> {
  static const _handleWidth = 16.0;
  static const _frameStripHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: _editCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _editBorder),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return _EditTrimRangeBar(
                width: constraints.maxWidth,
                stripHeight: _frameStripHeight,
                handleWidth: _handleWidth,
                frameThumbs: widget.frameThumbs,
                fallbackThumbnailPath: widget.fallbackThumbnailPath,
                range: widget.range,
                totalSeconds: widget.totalSeconds,
                onChanged: widget.onChanged,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(Duration.zero), style: _markerStyle),
              Text(
                _formatDuration(
                  Duration(milliseconds: (widget.totalSeconds * 1000).round()),
                ),
                style: _markerStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _markerStyle = TextStyle(
    color: _editMuted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );
}

class _EditTrimRangeBar extends StatefulWidget {
  final double width;
  final double stripHeight;
  final double handleWidth;
  final List<Uint8List?> frameThumbs;
  final String? fallbackThumbnailPath;
  final RangeValues range;
  final double totalSeconds;
  final _EditTimelineDragCallback? onChanged;

  const _EditTrimRangeBar({
    required this.width,
    required this.stripHeight,
    required this.handleWidth,
    required this.frameThumbs,
    required this.fallbackThumbnailPath,
    required this.range,
    required this.totalSeconds,
    required this.onChanged,
  });

  @override
  State<_EditTrimRangeBar> createState() => _EditTrimRangeBarState();
}

class _EditTrimRangeBarState extends State<_EditTrimRangeBar> {
  String? _activeHandle;

  double get _availableWidth => widget.width - widget.handleWidth * 2;

  double _secondsToX(double seconds) {
    final ratio = (seconds / widget.totalSeconds).clamp(0.0, 1.0);
    return widget.handleWidth + ratio * _availableWidth;
  }

  double _xToSeconds(double x) {
    final clamped = (x - widget.handleWidth).clamp(0.0, _availableWidth);
    if (_availableWidth <= 0) return 0;
    return (clamped / _availableWidth) * widget.totalSeconds;
  }

  void _onDragStart(String handle) {
    if (widget.onChanged == null) return;
    _activeHandle = handle;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final cb = widget.onChanged;
    if (cb == null || _activeHandle == null) return;
    final localX =
        (details.globalPosition.dx - _renderBoxOriginX()).clamp(0.0, widget.width);
    final sec = _xToSeconds(localX);
    if (_activeHandle == 'start') {
      cb(RangeValues(sec, widget.range.end), dragging: true);
    } else if (_activeHandle == 'end') {
      cb(RangeValues(widget.range.start, sec), dragging: true);
    } else if (_activeHandle == 'window') {
      final span = widget.range.end - widget.range.start;
      final dragMid = sec;
      var newStart = dragMid - span / 2;
      var newEnd = dragMid + span / 2;
      if (newStart < 0) {
        newStart = 0;
        newEnd = span;
      }
      if (newEnd > widget.totalSeconds) {
        newEnd = widget.totalSeconds;
        newStart = newEnd - span;
      }
      cb(RangeValues(newStart, newEnd), dragging: true);
    }
  }

  void _onDragEnd(_) {
    final cb = widget.onChanged;
    if (cb != null && _activeHandle != null) {
      cb(widget.range, dragging: false);
    }
    _activeHandle = null;
  }

  double _renderBoxOriginX() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    return box.localToGlobal(Offset.zero).dx;
  }

  @override
  Widget build(BuildContext context) {
    final startX = _secondsToX(widget.range.start);
    final endX = _secondsToX(widget.range.end);
    return SizedBox(
      width: widget.width,
      height: widget.stripHeight,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: List.generate(
                _editFrameCount,
                (i) {
                  final bytes = i < widget.frameThumbs.length
                      ? widget.frameThumbs[i]
                      : null;
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2230),
                        border: Border(
                          right: BorderSide(
                            color: Colors.black.withValues(alpha: 0.30),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: bytes != null
                          ? Image.memory(bytes, fit: BoxFit.cover)
                          : widget.fallbackThumbnailPath != null
                              ? Image.file(
                                  File(widget.fallbackThumbnailPath!),
                                  fit: BoxFit.cover,
                                  opacity:
                                      const AlwaysStoppedAnimation(0.35),
                                )
                              : const SizedBox.shrink(),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: startX,
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          Positioned(
            left: endX,
            top: 0,
            bottom: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          Positioned(
            left: startX,
            right: widget.width - endX,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _onDragStart('window'),
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: startX - widget.handleWidth,
            top: 0,
            bottom: 0,
            width: widget.handleWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _onDragStart('start'),
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: const _EditTrimHandle(side: 'left'),
            ),
          ),
          Positioned(
            left: endX,
            top: 0,
            bottom: 0,
            width: widget.handleWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _onDragStart('end'),
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: const _EditTrimHandle(side: 'right'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditTrimHandle extends StatelessWidget {
  final String side;

  const _EditTrimHandle({required this.side});

  @override
  Widget build(BuildContext context) {
    final isLeft = side == 'left';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.horizontal(
          left: isLeft ? const Radius.circular(6) : Radius.zero,
          right: isLeft ? Radius.zero : const Radius.circular(6),
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 3,
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

String _formatDuration(Duration? duration) {
  final d = duration ?? Duration.zero;
  final total = d.inSeconds;
  final minutes = (total ~/ 60).toString().padLeft(2, '0');
  final seconds = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
