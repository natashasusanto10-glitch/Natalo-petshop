import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../features/feed/widgets/feed_action_rail.dart';
import '../../features/feed/widgets/feed_creator_overlay.dart';
import '../../features/feed/widgets/feed_post_scrim.dart';
import '../../features/feed/widgets/feed_product_anchor_card.dart';
import '../../models/feed_create_post_draft.dart';
import '../../models/product.dart';
import '../../services/app_analytics.dart';
import '../../state/member_store.dart';
import '../../state/settings_store.dart';
import '../../utils/formatters.dart';
import '../../utils/haptics.dart';
import '../feed_new_post_screen.dart' show NewPostMediaDraft, NewPostMediaType, startTrimLoopGuard;

/// Hasil dari `FeedPostPreviewScreen` — dua aksi bawah preview:
///  - `share`     → user tap "Bagikan" di preview → langsung `_upload()`.
///  - `saveDraft` → user tap "Simpan Draft" di preview → `_saveDraftAndExit()`.
/// `null` (pop tanpa result / back) = kembali edit, tidak ada aksi.
enum FeedPreviewResult { share, saveDraft }

const _previewBlue = Color(0xFF1E5BFF);
// Tinggi bar aksi bawah preview (share/simpan draft) + jarak aman ke
// overlay rail/produk di atasnya — dipakai untuk offset `Positioned.bottom`
// rail aksi & grup kiri-bawah (produk/kreator/caption).
const _previewBottomBarHeight = 76.0;
const _previewOverlayGap = 28.0;

/// Layar Pratinjau — render chrome feed ASLI (widget bersama 2A) supaya
/// benar-benar semirip mungkin dengan tampilan publik. Suara AKTIF
/// (mengikuti `appSettingsStore.feedMuted`) — sebelumnya di-mute paksa,
/// bug user #3 "no sound in preview".
class FeedPostPreviewScreen extends StatefulWidget {
  final NewPostMediaDraft draft;
  final FeedCreatePostDraft? videoDraft;
  final String caption;

  /// Produk yang ditag — dipakai untuk render kartu produk (anchor card).
  final List<Product> products;

  const FeedPostPreviewScreen({
    super.key,
    required this.draft,
    required this.videoDraft,
    required this.caption,
    required this.products,
  });

  @override
  State<FeedPostPreviewScreen> createState() => _FeedPostPreviewScreenState();
}

class _FeedPostPreviewScreenState extends State<FeedPostPreviewScreen> {
  VideoPlayerController? _videoController;
  Timer? _trimGuard;
  bool _videoReady = false;
  int _photoIndex = 0;
  late final PageController _photoPageController;

  bool get _isVideo => widget.draft.type == NewPostMediaType.video;

  @override
  void initState() {
    super.initState();
    unawaited(
      AppAnalytics.logEvent('feed_post_preview_opened', {
        'type': _isVideo
            ? 'video'
            : (widget.draft.photoFiles.length > 1 ? 'carousel' : 'photo'),
      }),
    );
    _photoPageController = PageController();
    if (_isVideo) _initVideo();
  }

  @override
  void dispose() {
    _trimGuard?.cancel();
    _videoController?.dispose();
    _photoPageController.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final path = widget.videoDraft?.finalVideoPath;
    if (path == null) return;
    final controller = VideoPlayerController.file(File(path));
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) return;
      await controller.setLooping(true);
      // Suara AKTIF mengikuti preferensi global — bug fix #3: sebelumnya
      // hardcoded setVolume(0), pratinjau selalu bisu walau user tidak
      // memilih Senyap.
      await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
      await controller.play();
      setState(() => _videoReady = true);
      _trimGuard = startTrimLoopGuard(controller, widget.videoDraft);
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoReady = false);
    }
  }

  void _toggleMute() {
    final next = !appSettingsStore.feedMuted;
    unawaited(appSettingsStore.setFeedMuted(next));
    final ctrl = _videoController;
    if (ctrl != null && ctrl.value.isInitialized) {
      unawaited(ctrl.setVolume(next ? 0 : 1));
    }
    unawaited(AppHaptics.selection());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final products = widget.products;
    final profile = memberStore.profile;
    final muted = appSettingsStore.feedMuted;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Media fullscreen ──
          Positioned.fill(child: _buildMediaContent()),
          // ── Scrim bawah — kontras overlay caption/kreator/produk ──
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(child: FeedPostScrim()),
          ),
          // ── Top chrome: back + judul "Pratinjau" + toggle suara ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _PreviewRoundButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Pratinjau',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  _SoundPill(muted: muted, onTap: _toggleMute),
                ],
              ),
            ),
          ),
          // ── Rail kanan — chrome feed asli, non-interaktif ──
          Positioned(
            right: 4,
            bottom: bottomInset + _previewBottomBarHeight + _previewOverlayGap,
            child: const IgnorePointer(
              child: FeedActionRail(
                likeCount: 0,
                liked: false,
                commentCount: 0,
                shareCount: 0,
              ),
            ),
          ),
          // ── Grup kiri-bawah: kartu produk + identitas kreator + caption ──
          Positioned(
            left: 16,
            right: 78,
            bottom: bottomInset + _previewBottomBarHeight + _previewOverlayGap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (products.isNotEmpty) ...[
                  Builder(builder: (context) {
                    final p = products.first;
                    return FeedProductAnchorCard(
                      title: p.title,
                      imageUrl: p.imageUrl.isEmpty ? null : p.imageUrl,
                      priceText: formatRupiah(p.finalPrice),
                      strikePriceText:
                          p.hasDiscount ? formatRupiah(p.price) : null,
                      discountBadgeText: p.hasDiscount
                          ? 'Diskon ${p.discountPercent}%'
                          : null,
                    );
                  }),
                  const SizedBox(height: 12),
                ],
                FeedCreatorIdentity(
                  name: profile?.displayHandle ?? 'Kamu',
                  avatarInitial: profile?.initial ?? 'U',
                  avatarUrl: profile?.profilePhotoUrl,
                  // Admin login = brand Natalo → pratinjau tampil identitas
                  // brand (logo NL), konsisten dgn feed asli.
                  isOfficial: profile?.isAdmin ?? false,
                  followState: FeedFollowChipState.none,
                ),
                if (widget.caption.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  FeedExpandableCaption(text: widget.caption),
                ],
              ],
            ),
          ),
          // ── Bottom bar hitam: Simpan Draft + Bagikan ──
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(
                              context, FeedPreviewResult.saveDraft),
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                const Color.fromRGBO(255, 255, 255, 0.07),
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: Color.fromRGBO(255, 255, 255, 0.15),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Simpan Draft',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pop(context, FeedPreviewResult.share),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _previewBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Bagikan',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent() {
    if (_isVideo) {
      final ctrl = _videoController;
      if (_videoReady && ctrl != null && ctrl.value.isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
        );
      }
      final thumb = widget.videoDraft?.thumbnailPath;
      if (thumb != null) {
        return Image.file(File(thumb), fit: BoxFit.contain);
      }
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.4,
          ),
        ),
      );
    }
    // Photo / carousel.
    final files = widget.draft.photoFiles;
    if (files.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, color: Colors.white24, size: 64),
      );
    }
    if (files.length == 1) {
      return Image.file(files.first, fit: BoxFit.contain);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _photoPageController,
          itemCount: files.length,
          onPageChanged: (i) => setState(() => _photoIndex = i),
          itemBuilder: (context, index) {
            return Image.file(files[index], fit: BoxFit.contain);
          },
        ),
        Positioned(
          top: 70,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_photoIndex + 1}/${files.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _PreviewRoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Pill frosted "Suara"/"Senyap" — toggle mute preview, mengikuti pola
/// `appSettingsStore.feedMuted` global.
class _SoundPill extends StatelessWidget {
  final bool muted;
  final VoidCallback onTap;

  const _SoundPill({required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                muted ? 'Senyap' : 'Suara',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
