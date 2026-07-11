import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../utils/haptics.dart';
import '../../utils/video_frame_thumbs.dart';
import '../../widgets/app_toast.dart';

const _coverBlue = Color(0xFF1E5BFF);
const _coverInk = Color(0xFF101828);
const _coverMuted = Color(0xFF667085);
const _coverMarker = Color(0xFF98A2B3);
const _coverBorder = Color(0xFFE0E7F0);
const _coverGalleryBg = Color(0xFFF5F8FF);
const _coverFallback = Color(0xFF161A24);

const int _kFrameCount = 10;

/// Layar penuh light untuk pilih sampul (cover) video — filmstrip scrubber
/// IG-style. Frame diambil dari RENTANG TRIM (startMs..startMs+spanMs) pada
/// file video ASLI (offset absolut), bukan file yang sudah di-trim/kompres.
///
/// Return:
///  - `String` path JPEG sampul terpilih (dari `coverGenerator`, atau path
///    hasil pilih dari galeri).
///  - `null` bila user batal (tombol X / system back).
class FeedCoverPickerScreen extends StatefulWidget {
  final String videoPath;
  final Duration rangeStart;
  final Duration rangeSpan;
  final String? currentCoverPath;

  /// Injectable untuk widget test (default `VideoThumbnail.thumbnailData`
  /// maxWidth 120 quality 50) — dipakai FILMSTRIP saja (thumbnail kecil,
  /// banyak frame sekaligus).
  final Future<Uint8List?> Function(String path, int timeMs)? frameExtractor;

  /// Injectable untuk widget test — dipakai HERO PREVIEW besar (satu frame
  /// resolusi lebih tinggi, jadi jelas dilihat sebagai calon sampul).
  /// Default `VideoThumbnail.thumbnailData` maxWidth 720 quality 80. Beda
  /// dari [frameExtractor] yang dipakai filmstrip (120/q50) — hero preview
  /// butuh detail lebih tajam, filmstrip cukup thumbnail kecil.
  final Future<Uint8List?> Function(String path, int timeMs)?
      previewFrameExtractor;

  /// Generate file JPEG sampul final dari timestamp terpilih. Default
  /// `VideoThumbnail.thumbnailFile` (maxWidth 720, quality 82).
  final Future<String?> Function(String path, int timeMs)? coverGenerator;

  const FeedCoverPickerScreen({
    super.key,
    required this.videoPath,
    required this.rangeStart,
    required this.rangeSpan,
    this.currentCoverPath,
    this.frameExtractor,
    this.previewFrameExtractor,
    this.coverGenerator,
  });

  @override
  State<FeedCoverPickerScreen> createState() => _FeedCoverPickerScreenState();
}

class _FeedCoverPickerScreenState extends State<FeedCoverPickerScreen> {
  final List<Uint8List?> _frameThumbs =
      List<Uint8List?>.filled(_kFrameCount, null);
  double _fraction = 0.0;
  int _selectedMs = 0;
  Uint8List? _previewBytes;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _selectedMs = widget.rangeStart.inMilliseconds;
    _loadFilmstrip();
    _loadInitialPreview();
  }

  Future<void> _loadFilmstrip() async {
    await extractVideoFrameThumbs(
      videoPath: widget.videoPath,
      startMs: widget.rangeStart.inMilliseconds,
      spanMs: widget.rangeSpan.inMilliseconds,
      count: _kFrameCount,
      extractor: widget.frameExtractor,
      onFrame: (i, bytes) {
        if (!mounted) return;
        setState(() => _frameThumbs[i] = bytes);
      },
    );
  }

  /// Extract 1 frame TINGGI resolusi (720px/q80) — dipakai HERO PREVIEW
  /// besar (satu frame ditampilkan besar, jadi butuh detail lebih tajam
  /// daripada thumbnail filmstrip 120px/q50 yang dipakai `_loadFilmstrip`).
  /// Extractor terpisah dari filmstrip supaya sampul yang dilihat user
  /// tidak blur upscale dari thumbnail kecil.
  Future<Uint8List?> _extractPreview(String path, int timeMs) {
    final extractor = widget.previewFrameExtractor ??
        (String p, int t) => VideoThumbnail.thumbnailData(
              video: p,
              imageFormat: ImageFormat.JPEG,
              quality: 80,
              maxWidth: 720,
              timeMs: t,
            );
    return extractor(path, timeMs);
  }

  /// Hero preview awal (posisi rangeStart) — dipanggil paralel dengan
  /// filmstrip di initState, hi-res langsung (tidak lagi numpang frame
  /// 0 filmstrip yang cuma 120px/q50).
  Future<void> _loadInitialPreview() async {
    try {
      final bytes = await _extractPreview(widget.videoPath, _selectedMs);
      if (!mounted) return;
      setState(() => _previewBytes = bytes);
    } catch (_) {
      // Preview gagal — biarkan fallback (currentCoverPath / placeholder).
    }
  }

  Future<void> _onDragUpdate(double fraction) async {
    setState(() => _fraction = fraction.clamp(0.0, 1.0));
  }

  Future<void> _onDragEnd() async {
    final absoluteMs =
        widget.rangeStart.inMilliseconds + (_fraction * widget.rangeSpan.inMilliseconds).round();
    setState(() => _selectedMs = absoluteMs);
    try {
      final bytes = await _extractPreview(widget.videoPath, absoluteMs);
      if (!mounted) return;
      setState(() => _previewBytes = bytes);
    } catch (_) {
      // Preview gagal — biarkan preview lama tampil, tidak fatal.
    }
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    AppHaptics.tap();
    try {
      final generator = widget.coverGenerator ??
          (String p, int t) => VideoThumbnail.thumbnailFile(
                video: p,
                imageFormat: ImageFormat.JPEG,
                maxWidth: 720,
                timeMs: t,
                quality: 82,
              );
      final path = await generator(widget.videoPath, _selectedMs);
      if (!mounted) return;
      if (path == null) {
        AppToast.show(context, 'Gagal membuat sampul. Coba lagi.',
            kind: ToastKind.error);
        setState(() => _confirming = false);
        return;
      }
      Navigator.of(context).pop(path);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal membuat sampul. Coba lagi.',
          kind: ToastKind.error);
      setState(() => _confirming = false);
    }
  }

  Future<void> _pickFromGallery() async {
    AppHaptics.tap();
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      Navigator.of(context).pop(picked.path);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Gagal membuka galeri.', kind: ToastKind.error);
    }
  }

  String _timecode(int ms) {
    final total = Duration(milliseconds: ms);
    final m = total.inMinutes;
    final s = total.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onClose: () => Navigator.of(context).pop(), onConfirm: _confirm),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Pilih frame dari video, atau ambil gambar dari galeri.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _coverMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Expanded + FractionallySizedBox supaya preview mengisi ruang
            // yang tersedia (bounded) tanpa overflow di layar pendek,
            // tetap ~52% lebar layar & aspect 2:3 (per spec visual).
            Expanded(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.52,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox.expand(
                            child: _previewBytes != null
                                ? Image.memory(
                                    _previewBytes!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        Container(color: _coverFallback),
                                  )
                                : (widget.currentCoverPath != null
                                    ? Image.file(
                                        File(widget.currentCoverPath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(color: _coverFallback),
                                      )
                                    : Container(color: _coverFallback)),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _timecode(_selectedMs),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Filmstrip(
                frames: _frameThumbs,
                fraction: _fraction,
                onDragUpdate: _onDragUpdate,
                onDragEnd: _onDragEnd,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '0:00',
                    style: TextStyle(
                      color: _coverMarker,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _timecode(widget.rangeSpan.inMilliseconds),
                    style: const TextStyle(
                      color: _coverMarker,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _coverGalleryBg,
                    side: const BorderSide(color: _coverBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library_outlined,
                      color: _coverBlue, size: 20),
                  label: const Text(
                    'Ambil dari galeri',
                    style: TextStyle(
                      color: _coverBlue,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  const _Header({required this.onClose, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _CircleIconButton(
                icon: Icons.close_rounded,
                iconColor: _coverInk,
                bgColor: Colors.white,
                borderColor: _coverBorder,
                onTap: onClose,
              ),
            ),
            const Center(
              child: Text(
                'Ubah Sampul',
                style: TextStyle(
                  color: _coverInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _CircleIconButton(
                icon: Icons.check_rounded,
                iconColor: Colors.white,
                bgColor: _coverBlue,
                borderColor: _coverBlue,
                onTap: onConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      shape: CircleBorder(side: BorderSide(color: borderColor)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  final List<Uint8List?> frames;
  final double fraction;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _Filmstrip({
    required this.frames,
    required this.fraction,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  void _handleDrag(double dx, double width) {
    onDragUpdate((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final boxWidth = width / frames.length;
        final boxLeft =
            (fraction * (width - boxWidth)).clamp(0.0, width - boxWidth);

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox;
            final local = box.globalToLocal(details.globalPosition);
            _handleDrag(local.dx, width);
          },
          onHorizontalDragEnd: (_) => onDragEnd(),
          onTapUp: (details) {
            final box = context.findRenderObject() as RenderBox;
            final local = box.globalToLocal(details.globalPosition);
            _handleDrag(local.dx, width);
            onDragEnd();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 54,
              width: width,
              child: Stack(
                children: [
                  Row(
                    children: List.generate(frames.length, (i) {
                      final bytes = frames[i];
                      return Expanded(
                        child: bytes != null
                            ? Image.memory(
                                bytes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Container(color: _coverFallback),
                              )
                            : Container(color: _coverFallback),
                      );
                    }),
                  ),
                  // Dim putih 0.55 di luar kotak seleksi.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: boxLeft,
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  Positioned(
                    left: boxLeft + boxWidth,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  Positioned(
                    left: boxLeft,
                    top: 0,
                    bottom: 0,
                    width: boxWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: _coverBlue, width: 3),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
