import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../models/product.dart';
import '../../../services/follow_service.dart';
import '../../../state/cart_store.dart';
import '../../../state/follow_override_store.dart';
import '../../../state/member_store.dart';
import '../../../utils/formatters.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/official_brand_avatar.dart';
import '../../../widgets/post_likers_sheet.dart';
import 'feed_action_rail.dart';
import 'feed_creator_overlay.dart';
import 'feed_product_anchor_card.dart';
import 'feed_product_pill.dart';

/// Public/shared widgets used by BOTH `_PhotoCarouselPostView` (in
/// `feed_screen.dart`) and `FeedVideoPostView`
/// (`feed_video_post_view.dart`). Extracted here to keep exactly one
/// implementation and avoid visual drift between the photo and video
/// call sites, without creating a circular import between those two
/// files.
const feedPostGoldColor = Color(0xFFF4D47C);

/// Caption memakai gap 16dp. Rail memakai gap 4dp supaya pusat action paling
/// bawah sejajar dengan baris metadata/social proof; kedua nilai tetap dipakai
/// konsisten oleh post foto dan video.
const feedPostOverlayBottomGap = 16.0;
const feedPostActionRailBottomGap = 4.0;
const feedPostActionRailRightInset = 10.0;

/// Instagram-style social proof shown below the caption in Feed/fullscreen.
/// The data remains owned by [FeedPost], so Feed, Postingan, and fullscreen
/// all render the same server-backed liker snapshot.
class FeedPostSocialProof extends StatelessWidget {
  final FeedPost post;

  const FeedPostSocialProof({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    if (post.likeCount <= 0) return const SizedBox.shrink();
    final primary = post.recentLikers.isNotEmpty
        ? post.recentLikers.first
        : null;
    final primaryName = primary?.displayName ?? 'beberapa orang';
    final others = post.likeCount - 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => PostLikersSheet.show(context, postId: post.id),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            _FeedSocialProofAvatars(
              likers: post.recentLikers,
              likeCount: post.likeCount,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Disukai oleh '),
                    TextSpan(
                      text: primaryName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (others > 0) ...[
                      const TextSpan(text: ' dan '),
                      TextSpan(
                        text: '$others orang lainnya',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedSocialProofAvatars extends StatelessWidget {
  final List<FeedAuthor> likers;
  final int likeCount;

  const _FeedSocialProofAvatars({required this.likers, required this.likeCount});

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    final visible = likers.take(2).toList(growable: false);
    final hasOthers = likeCount > 1;
    return SizedBox(
      width: hasOthers ? size + 12 : size,
      height: size,
      child: Stack(
        children: [
          if (hasOthers)
            Positioned(
              left: 10,
              child: _avatar(visible.length > 1 ? visible[1] : null, size),
            ),
          Positioned(
            left: 0,
            child: _avatar(visible.isNotEmpty ? visible.first : null, size),
          ),
        ],
      ),
    );
  }

  Widget _avatar(FeedAuthor? author, double size) {
    if (author?.isOfficialAccount == true) {
      return OfficialBrandAvatar(size: size);
    }
    final url = author?.profilePhotoUrl;
    return ClipOval(
      child: url == null || url.isEmpty
          ? Container(
              width: size,
              height: size,
              color: Colors.white.withValues(alpha: 0.75),
              alignment: Alignment.center,
              child: Text(
                (author?.displayName ?? 'N').characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
            )
          : CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
    );
  }
}

@visibleForTesting
bool resolveFeedAuthorFollowStateForViewer({
  required bool authorSnapshot,
  required int snapshotViewerGeneration,
  required int activeViewerGeneration,
  required bool? override,
  required bool? canonical,
  required int? canonicalViewerGeneration,
}) {
  if (override != null) return override;
  if (canonicalViewerGeneration == activeViewerGeneration &&
      canonical != null) {
    return canonical;
  }
  if (snapshotViewerGeneration == activeViewerGeneration) {
    return authorSnapshot;
  }
  return false;
}

/// Jarak dasar overlay bawah feed (rail durasi / caption / action rail)
/// dari tepi bawah layar — dipakai SEMUA state (loading, foto, video)
/// supaya spacing konsisten.
double feedPostOverlayBaseInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 4.0;

/// Dipakai `_PhotoCarouselPostViewState` (feed_screen.dart) untuk foto —
/// juga dipertahankan di sini karena sebelumnya dipakai kedua sisi (foto +
/// video) sebelum polish menghilangkan pemakaian di sisi video.
double feedPostInstagramImageAspectRatio(int? width, int? height) {
  final w = width ?? 0;
  final h = height ?? 0;
  if (w <= 0 || h <= 0) return 4 / 5;
  final ratio = w / h;
  if (ratio.isNaN || ratio.isInfinite || ratio <= 0) return 4 / 5;
  return ratio.clamp(4 / 5, 1.91).toDouble();
}

class FeedPostCreatorIdentity extends StatefulWidget {
  final FeedAuthor author;
  final String displayName;

  const FeedPostCreatorIdentity({
    required this.author,
    required this.displayName,
  });

  @override
  State<FeedPostCreatorIdentity> createState() =>
      _FeedPostCreatorIdentityState();
}

class _FeedPostCreatorIdentityState extends State<FeedPostCreatorIdentity> {
  bool _busy = false;
  late int _activeViewerGeneration;
  late int _snapshotViewerGeneration;
  int? _canonicalViewerGeneration;
  bool? _canonicalFollowing;

  @override
  void initState() {
    super.initState();
    _activeViewerGeneration = memberStore.viewerGeneration;
    _snapshotViewerGeneration = _activeViewerGeneration;
    memberStore.addListener(_onViewerChanged);
  }

  @override
  void didUpdateWidget(covariant FeedPostCreatorIdentity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.author.id != widget.author.id) {
      _snapshotViewerGeneration = memberStore.viewerGeneration;
      _canonicalViewerGeneration = null;
      _canonicalFollowing = null;
    } else if (_snapshotViewerGeneration == memberStore.viewerGeneration &&
        oldWidget.author.isFollowing != widget.author.isFollowing) {
      // A same-generation server refresh may replace the original snapshot.
      // Once a viewer switch invalidates it (-1), widget updates cannot make
      // an old response trustworthy again; only fetchState can do that.
      _snapshotViewerGeneration = memberStore.viewerGeneration;
    }
  }

  @override
  void dispose() {
    memberStore.removeListener(_onViewerChanged);
    super.dispose();
  }

  void _onViewerChanged() {
    final generation = memberStore.viewerGeneration;
    if (generation == _activeViewerGeneration) return;
    _activeViewerGeneration = generation;
    _snapshotViewerGeneration = -1;
    _canonicalViewerGeneration = null;
    _canonicalFollowing = null;
    _busy = false;
    if (mounted) setState(() {});
    unawaited(_refreshFollowStateForViewer(generation, widget.author.id));
  }

  Future<void> _refreshFollowStateForViewer(
    int viewerGeneration,
    String authorId,
  ) async {
    if (authorId.isEmpty || memberStore.profile?.id == authorId) return;
    try {
      final state = await followService.fetchState(authorId);
      if (!mounted ||
          memberStore.viewerGeneration != viewerGeneration ||
          widget.author.id != authorId) {
        return;
      }
      setState(() {
        _canonicalViewerGeneration = viewerGeneration;
        _canonicalFollowing = state.isFollowing;
      });
    } on FollowSessionChangedException {
      // A newer viewer generation owns the chip now.
    } catch (_) {
      // Revalidation is best-effort. The stale snapshot remains suppressed.
    }
  }

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    if (_busy) return;
    AppHaptics.tap();
    if (!memberStore.isLoggedIn) {
      Navigator.pushNamed(context, '/member/login');
      return;
    }
    _busy = true;
    final author = widget.author;
    final target = !currentlyFollowing;
    // Optimistic — chip (dan semua chip author sama di post lain)
    // langsung berubah; revert kalau API gagal.
    setFollowOverride(author.id, target);
    try {
      if (target) {
        await followService.follow(author.id);
      } else {
        await followService.unfollow(author.id);
      }
    } on FollowSessionChangedException {
      // The response belongs to the previous authenticated viewer. The new
      // session owns the global follow state, so do not show a false error or
      // publish any rollback from the old account.
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Gagal memperbarui. Coba lagi.');
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.author;
    // Identity tap-able buat user dengan username — buka public profile
    // /u/{username}. Official account tetap non-tappable (admin = brand
    // tunggal, gak ada profile page sendiri). User tanpa username
    // (existing yang belum set) gak tappable juga supaya gak nge-route
    // ke handle null.
    final canOpenProfile = author.hasUsername;
    final trimmedName = widget.displayName.trim();
    final avatarInitial =
        trimmedName.isEmpty ? 'N' : trimmedName[0].toUpperCase();

    // AnimatedBuilder ke memberStore + ValueListenableBuilder ke
    // followOverrides supaya chip hilang/muncul & label berubah benar
    // saat login state / follow state berubah tanpa perlu feed re-fetch.
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        final selfId = memberStore.profile?.id;
        final isSelf = selfId != null && selfId == author.id;
        return ValueListenableBuilder<Map<String, bool>>(
          valueListenable: followOverrides,
          builder: (context, overrides, _) {
            final following = resolveFeedAuthorFollowStateForViewer(
              authorSnapshot: author.isFollowing,
              snapshotViewerGeneration: _snapshotViewerGeneration,
              activeViewerGeneration: memberStore.viewerGeneration,
              override: overrides[author.id],
              canonical: _canonicalFollowing,
              canonicalViewerGeneration: _canonicalViewerGeneration,
            );
            // Akun official KINI bisa di-follow (brand punya handle
            // "natalopetshop"); hanya self yang tidak dapat chip (tak bisa
            // follow diri sendiri).
            final followState = isSelf
                ? FeedFollowChipState.hidden
                : (following
                    ? FeedFollowChipState.following
                    : FeedFollowChipState.none);
            return FeedCreatorIdentity(
              name: widget.displayName,
              avatarInitial: avatarInitial,
              avatarUrl: author.profilePhotoUrl,
              isOfficial: author.isOfficialAccount,
              followState: followState,
              onFollowTap: followState == FeedFollowChipState.hidden
                  ? null
                  : () => _toggleFollow(following),
              // POIN 5 (guard navigasi langsung ke profil) — keputusan:
              // DOKUMENTASI-SAJA, tanpa plumbing pause eksplisit. Alasan:
              //  (1) FeedVideoPostView.didPushNext (RouteAware) mem-pause video
              //      Feed SINKRON begitu route '/u' didorong — sebelum profil
              //      sempat menutupi Feed — dan mencatat `_routeCovered=true`.
              //  (2) Master-guard `_feedRouteIsCurrent` (isCurrent) menahan
              //      SEMUA jalur play() legacy selama route lain menutupi Feed,
              //      apa pun state bookkeeping.
              // Kedua lapis itu sudah menutup celah audio-hantu Feed→Profile.
              // Widget identity ini dipakai bersama (foto + video + detail),
              // TIDAK punya binding langsung ke state video; menambah callback
              // pause menembus beberapa lapis widget = invasif + berisiko ke
              // struktur bersama tanpa manfaat tambahan. Jadi tidak di-plumb.
              onProfileTap: canOpenProfile
                  ? () {
                      AppHaptics.tap();
                      Navigator.pushNamed(
                        context,
                        '/u',
                        arguments: author.username!.toLowerCase(),
                      );
                    }
                  : null,
            );
          },
        );
      },
    );
  }
}

class FeedPostSnapBackZoomMedia extends StatefulWidget {
  final Widget child;
  final Clip clipBehavior;
  final double minScale;
  final double maxScale;
  final ValueChanged<bool>? onZoomingChanged;

  const FeedPostSnapBackZoomMedia({
    required this.child,
    this.clipBehavior = Clip.hardEdge,
    this.minScale = 1,
    this.maxScale = 4,
    this.onZoomingChanged,
  });

  @override
  State<FeedPostSnapBackZoomMedia> createState() =>
      _FeedPostSnapBackZoomMediaState();
}

class _FeedPostSnapBackZoomMediaState extends State<FeedPostSnapBackZoomMedia>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapBackController;
  final Map<int, Offset> _activePointers = {};
  Animation<double>? _snapBackAnimation;
  double _scale = 1;
  double _gestureStartScale = 1;
  double _gestureStartDistance = 1;
  bool _pinching = false;
  bool _notifiedZooming = false;

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_handleSnapBackTick);
  }

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 2) {
      _startPinch();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;
    if (!_pinching || _activePointers.length < 2) return;

    final distance = _currentPointerDistance();
    if (distance <= 0 || _gestureStartDistance <= 0) return;

    final nextScale = (_gestureStartScale * distance / _gestureStartDistance)
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    if ((nextScale - _scale).abs() < 0.001) return;
    setState(() => _scale = nextScale);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_pinching && _activePointers.length < 2) {
      _endPinch();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_pinching && _activePointers.length < 2) {
      _endPinch();
    }
  }

  void _startPinch() {
    if (_snapBackController.isAnimating) {
      _snapBackController.stop();
    }
    _pinching = true;
    _setZooming(true);
    _gestureStartScale = _scale;
    _gestureStartDistance = math.max(1.0, _currentPointerDistance());
  }

  void _endPinch() {
    _pinching = false;
    if ((_scale - widget.minScale).abs() <= 0.001) {
      setState(() => _scale = widget.minScale);
      _setZooming(false);
      return;
    }

    _snapBackAnimation = Tween<double>(
      begin: _scale,
      end: widget.minScale,
    ).animate(
      CurvedAnimation(
        parent: _snapBackController,
        curve: Curves.easeOutCubic,
      ),
    );
    _snapBackController.forward(from: 0);
  }

  void _handleSnapBackTick() {
    final animation = _snapBackAnimation;
    if (animation == null) return;
    setState(() => _scale = animation.value);
    if (_snapBackController.isCompleted) {
      _setZooming(false);
    }
  }

  void _setZooming(bool zooming) {
    if (_notifiedZooming == zooming) return;
    _notifiedZooming = zooming;
    widget.onZoomingChanged?.call(zooming);
  }

  double _currentPointerDistance() {
    if (_activePointers.length < 2) return 0;
    final points = _activePointers.values.take(2).toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.translucent,
      child: ClipRect(
        clipBehavior: widget.clipBehavior,
        child: Transform.scale(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Video player kalau ada videoUrl, fallback thumbnail kalau tidak.

class FeedPostBurstHeart extends StatelessWidget {
  const FeedPostBurstHeart();

  // 104 (dari 128 Material) — IG sedikit lebih ramping; kedua render site
  // (video + foto) memakai kotak 104 yang sama.
  static const double size = 104;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: size,
      width: size,
      child: CustomPaint(painter: FeedPostBurstHeartPainter()),
    );
  }
}

class FeedPostBurstHeartPainter extends CustomPainter {
  const FeedPostBurstHeartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildFeedHeartPath(size);
    final shadowPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawPath(path.shift(const Offset(0, 3)), shadowPaint);

    final fillPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Subtree overlay hati burst double-tap yang TERBANG ke tombol like rail.
///
/// - [tap]: titik jari (koordinat Stack ≈ global — media detector mengisi
///   layar dari (0,0)). Null → tampil di tengah.
/// - [target]: pusat tombol like rail; null (mis. key belum ter-render) →
///   fade di tempat tanpa terbang.
/// - [travel] 0→1: interpolasi posisi tap→target. [scale]/[opacity] dari
///   TweenSequence burst (pop di titik jari, lalu mengecil + memudar saat
///   melesat ke rail).
///
/// Return nested Stack supaya bisa jadi child langsung AnimatedBuilder
/// (Positioned wajib punya Stack parent).
Widget feedPostBuildFlyingBurstHeart({
  required Offset? tap,
  required Offset? target,
  required double scale,
  required double opacity,
  required double travel,
  required Size screenSize,
}) {
  if (opacity == 0) return const SizedBox.shrink();
  final origin = tap ?? Offset(screenSize.width / 2, screenSize.height / 2);
  final pos = target != null ? Offset.lerp(origin, target, travel)! : origin;
  return Stack(
    children: [
      Positioned(
        left: pos.dx - FeedPostBurstHeart.size / 2,
        top: pos.dy - FeedPostBurstHeart.size / 2,
        width: FeedPostBurstHeart.size,
        height: FeedPostBurstHeart.size,
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: const FeedPostBurstHeart(),
          ),
        ),
      ),
    ],
  );
}

/// Compact product pill — Final Lock Spec Feed Product Tag.
///
/// Layout: `[icon bag biru] [Diskon X% merah] | [Nama produk putih] [chevron]`
/// - Icon bag biru Natalo + stroke putih (per spec mockup).
/// - Diskon X% warna merah hanya tampil kalau hasActiveDiscount.
/// - Separator `|` warna white32.
/// - Nama produk 1 baris truncate.
/// - Chevron bawah → onTap buka bottom sheet "Lihat Produk".
/// - Background: dark translucent (Colors.black 0.55) + backdrop blur.
/// - No quick-add button (removed per spec) — full pill area tap-to-open.

class FeedPostTaggedProductsSheet extends StatelessWidget {
  final List<FeedProductLink> products;
  final Future<void> Function(FeedProductLink product) onOpenProduct;
  final Future<void> Function(FeedProductLink product, int quantity) onAdd;
  final Future<void> Function(FeedProductLink product, int quantity) onBuy;

  const FeedPostTaggedProductsSheet({
    required this.products,
    required this.onOpenProduct,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    // Cek apakah ANY product punya diskon aktif → tampilkan banner promo
    // di atas list. Banner umum (highest discount %) supaya 1 sheet bisa
    // cover multi-product video tagging.
    final discounted = products.where((p) => p.hasActiveDiscount).toList();
    final bannerPercent = discounted.isEmpty
        ? 0
        : discounted
            .map((p) => p.discountPercent)
            .reduce((a, b) => a > b ? a : b);
    return FractionallySizedBox(
      heightFactor: 0.62,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // ── Header row: title (left) + cart icon + X close (right) ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Lihat Produk (${products.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    // Cart icon dengan badge count — tap → buka Keranjang.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.pushNamed('/cart');
                      },
                      child: AnimatedBuilder(
                        animation: cartStore,
                        builder: (context, _) {
                          final count = cartStore.totalQuantity;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF1E5BFF),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Color(0xFF1E5BFF),
                                  size: 20,
                                ),
                              ),
                              if (count > 0)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFA726),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFF0B0D12),
                                        width: 1.4,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Tutup',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Banner promo (kalau ada produk diskon) ──
                if (bannerPercent > 0) ...[
                  _VideoPromoBanner(percent: bannerPercent),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _FeedTaggedProductCard(
                        product: product,
                        onOpenProduct: () async {
                          Navigator.of(context).pop();
                          await onOpenProduct(product);
                        },
                        onAdd: (quantity) => onAdd(product, quantity),
                        onBuy: (quantity) async {
                          Navigator.of(context).pop();
                          await onBuy(product, quantity);
                        },
                      );
                    },
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

/// Banner promo di atas product list bottom sheet.
/// Layout: [icon discount oranye] [Diskon X% merah / "Khusus untuk produk
/// di video ini" putih].
class _VideoPromoBanner extends StatelessWidget {
  final int percent;

  const _VideoPromoBanner({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2F36)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D4F).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              color: Color(0xFFFF4D4F),
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diskon $percent%',
                  style: const TextStyle(
                    color: Color(0xFFFF4D4F),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Khusus untuk produk di video ini',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedTaggedProductCard extends StatefulWidget {
  final FeedProductLink product;
  final Future<void> Function() onOpenProduct;
  final Future<void> Function(int quantity) onAdd;
  final Future<void> Function(int quantity) onBuy;

  const _FeedTaggedProductCard({
    required this.product,
    required this.onOpenProduct,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  State<_FeedTaggedProductCard> createState() => _FeedTaggedProductCardState();
}

class _FeedTaggedProductCardState extends State<_FeedTaggedProductCard> {
  int _quantity = 1;

  FeedProductLink get product => widget.product;

  void _decQty() {
    if (_quantity <= 1) return;
    AppHaptics.tap();
    setState(() => _quantity -= 1);
  }

  void _incQty() {
    final maxQty = math.max(1, product.stock);
    if (_quantity >= maxQty) return;
    AppHaptics.tap();
    setState(() => _quantity += 1);
  }

  @override
  Widget build(BuildContext context) {
    final pricing = feedPostProductPricing(product);
    final unavailable = !product.isAvailable || product.stock <= 0;
    final hasRatingData = product.avgRating > 0 || product.soldCount > 0;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF111820),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF242B33)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              onTap: widget.onOpenProduct,
              borderRadius: BorderRadius.circular(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FeedProductThumb(url: product.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.8,
                            fontWeight: FontWeight.w900,
                            height: 1.16,
                          ),
                        ),
                        // ── Badges row: Diskon X% merah ──
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (pricing.hasPromo)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFFF4D4F),
                                    width: 1.2,
                                  ),
                                ),
                                child: Text(
                                  'Diskon ${pricing.discountPercent}%',
                                  style: const TextStyle(
                                    color: Color(0xFFFF4D4F),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // ── Rating + terjual row ──
                        if (hasRatingData) ...[
                          const SizedBox(height: 7),
                          FeedPostProductRatingRow(
                            avgRating: product.avgRating,
                            soldCount: product.soldCount,
                          ),
                        ],
                        // ── Harga row: original (coret grey) + display (merah) ──
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 7,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (pricing.hasPromo)
                              Text(
                                formatRupiah(pricing.originalPrice),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.42),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor:
                                      Colors.white.withValues(alpha: 0.42),
                                ),
                              ),
                            Text(
                              formatRupiah(pricing.displayPrice),
                              style: TextStyle(
                                // Spec: harga diskon merah, harga normal merah
                                // juga (no separation). Konsisten satu warna.
                                color: pricing.hasPromo
                                    ? const Color(0xFFFF4D4F)
                                    : const Color(0xFFFF4D4F),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        if (unavailable) ...[
                          const SizedBox(height: 7),
                          const Text(
                            'Produk tidak tersedia',
                            style: TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!unavailable && !product.hasVariants) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Jumlah',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.60),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FeedProductQtyStepper(
                    quantity: _quantity,
                    maxQuantity: math.max(1, product.stock),
                    onMinus: _decQty,
                    onPlus: _incQty,
                  ),
                  const Spacer(),
                  Text(
                    'Total ${formatRupiah(pricing.displayPrice * _quantity)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (product.hasVariants)
              SizedBox(
                width: double.infinity,
                child: _FeedPrimaryProductButton(
                  label: 'Pilih Varian',
                  enabled: !unavailable,
                  onPressed: widget.onOpenProduct,
                ),
              )
            else
              Row(
                children: [
                  _FeedSmallCartButton(
                    enabled: !unavailable,
                    onPressed: () => widget.onAdd(_quantity),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FeedPrimaryProductButton(
                      label: 'Beli Sekarang',
                      enabled: !unavailable,
                      onPressed: () => widget.onBuy(_quantity),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedProductQtyStepper extends StatelessWidget {
  final int quantity;
  final int maxQuantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _FeedProductQtyStepper({
    required this.quantity,
    required this.maxQuantity,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FeedQtyCircleButton(
            icon: Icons.remove_rounded,
            enabled: quantity > 1,
            onTap: onMinus,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _FeedQtyCircleButton(
            icon: Icons.add_rounded,
            enabled: quantity < maxQuantity,
            onTap: onPlus,
          ),
        ],
      ),
    );
  }
}

class _FeedQtyCircleButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _FeedQtyCircleButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 17,
      child: SizedBox(
        height: 28,
        width: 28,
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: enabled ? 0.90 : 0.25),
          size: 18,
        ),
      ),
    );
  }
}

class _FeedSmallCartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _FeedSmallCartButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Cart icon button — blue line tema Natalo (spec ganti dari gold).
    // Filled biru transparan saat enabled, outline aja saat disabled.
    return SizedBox(
      height: 45,
      width: 45,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          backgroundColor: enabled
              ? const Color(0xFF1E5BFF).withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          foregroundColor: enabled
              ? const Color(0xFF1E5BFF)
              : Colors.white.withValues(alpha: 0.28),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
          side: BorderSide(
            color: const Color(0xFF1E5BFF)
                .withValues(alpha: enabled ? 0.55 : 0.12),
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.shopping_cart_outlined, size: 20),
      ),
    );
  }
}

/// Rating + terjual row — "★ 4.9 · 73,6 rb+ terjual" / hanya yang ada.
/// Star kuning saturated, divider dot abu, text white70.
class FeedPostProductRatingRow extends StatelessWidget {
  final double avgRating;
  final int soldCount;

  const FeedPostProductRatingRow({
    required this.avgRating,
    required this.soldCount,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = avgRating > 0;
    final hasSold = soldCount > 0;
    if (!hasRating && !hasSold) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasRating) ...[
          const Icon(
            Icons.star_rounded,
            color: Color(0xFFFFB400),
            size: 14,
          ),
          const SizedBox(width: 3),
          Text(
            avgRating.toStringAsFixed(1).replaceAll('.', ','),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
        if (hasRating && hasSold) ...[
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 10,
            color: Colors.white.withValues(alpha: 0.22),
          ),
          const SizedBox(width: 8),
        ],
        if (hasSold)
          Text(
            '${_formatSoldShort(soldCount)} terjual',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
      ],
    );
  }
}

/// Format jumlah terjual: 73,6 rb+ / 1,2 jt+ / 250+ / 12.
/// Local helper supaya tidak butuh import dari product_card.dart yang
/// pulls in widget lain.
String _formatSoldShort(int value) {
  if (value >= 1000000) {
    final d = value / 1000000;
    final fixed = d >= 10 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return '${fixed.replaceAll('.', ',').replaceAll(',0', '')} jt+';
  }
  if (value >= 1000) {
    final d = value / 1000;
    final fixed = d >= 10 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return '${fixed.replaceAll('.', ',').replaceAll(',0', '')} rb+';
  }
  if (value >= 100) return '${(value ~/ 50) * 50}+';
  return '$value';
}

class _FeedPrimaryProductButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _FeedPrimaryProductButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 45,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF5FBFFF),
                      Color(0xFF1E87FF),
                      Color(0xFF1261DA),
                    ],
                    stops: [0.0, 0.48, 1.0],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.07),
                    ],
                  ),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFBFDBFE).withValues(alpha: 0.62)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF399AFF).withValues(alpha: 0.32),
                      blurRadius: 24,
                      offset: const Offset(0, 9),
                    ),
                  ]
                : const [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.42),
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedProductThumb extends StatelessWidget {
  final String? url;

  const _FeedProductThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 66,
        width: 66,
        child: imageUrl.isEmpty
            ? const ColoredBox(
                color: Color(0xFF171B22),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: Colors.white70,
                ),
              )
            : imageUrl.startsWith('assets/')
                ? Image.asset(imageUrl, fit: BoxFit.cover)
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF171B22),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ),
      ),
    );
  }
}

class FeedPostProductPricing {
  final int originalPrice;
  final int displayPrice;
  final bool hasPromo;
  final int discountPercent;

  const FeedPostProductPricing({
    required this.originalPrice,
    required this.displayPrice,
    required this.hasPromo,
    required this.discountPercent,
  });
}

/// Diskon tertinggi (0..99) di antara produk tag yang promo. 0 = tak ada promo.
/// Pakai getter FeedProductLink.discountPercent (round+clamp) supaya konsisten
/// dengan badge kartu; produk non-promo return 0 sehingga otomatis terabaikan.
int feedMaxDiscountPercent(List<FeedProductLink> products) => products.fold<int>(
      0,
      (max, p) => p.discountPercent > max ? p.discountPercent : max,
    );

/// Bangun `FeedProductPill` (widget bersama) dari daftar produk tag + index
/// yang sedang tampil. Count = jumlah produk; badge diskon = persen tertinggi.
/// Rotasi index dikendalikan pemanggil (host feed). `onTap` membuka sheet Links.
Widget feedProductPillFor(
  List<FeedProductLink> products,
  int featuredIndex, {
  required VoidCallback onTap,
}) {
  if (products.isEmpty) return const SizedBox.shrink();
  final featured = products[featuredIndex % products.length];
  return FeedProductPill(
    title: featured.name,
    count: products.length,
    maxDiscountPercent: feedMaxDiscountPercent(products),
    onTap: onTap,
  );
}

FeedPostProductPricing feedPostProductPricing(FeedProductLink product) {
  final original = product.price;
  var display = product.price;
  final discount = product.discountPrice;
  final promo = product.promoPrice;
  if (discount != null && discount > 0 && discount < display) {
    display = discount;
  }
  if (promo != null && promo > 0 && promo < display) {
    display = promo;
  }
  final hasPromo = original > 0 && display < original;
  final percent = hasPromo
      ? (((original - display) / original) * 100).round().clamp(1, 99)
      : 0;
  return FeedPostProductPricing(
    originalPrice: original,
    displayPrice: display,
    hasPromo: hasPromo,
    discountPercent: percent,
  );
}

/// Bangun `FeedProductAnchorCard` (widget bersama, API primitif) dari
/// `FeedProductLink` — memformat rupiah + teks badge diskon di sini,
/// dipanggil dari `_PhotoCarouselPostViewState` & `_ProductCommerceOverlayGroup`.
FeedProductAnchorCard feedPostProductAnchorCardFor(
  FeedProductLink product, {
  required VoidCallback onTap,
  VoidCallback? onAddToCart,
}) {
  final pricing = feedPostProductPricing(product);
  final badgeText = product.hasActiveDiscount
      ? (product.isFlashSale
          ? 'Flash Sale ${product.discountPercent}%'
          : 'Diskon ${product.discountPercent}%')
      : null;
  return FeedProductAnchorCard(
    title: product.name,
    imageUrl: product.imageUrl,
    priceText: formatRupiah(pricing.displayPrice),
    strikePriceText:
        pricing.hasPromo ? formatRupiah(pricing.originalPrice) : null,
    discountBadgeText: badgeText,
    onTap: onTap,
    onAddToCart: onAddToCart,
  );
}

Product feedPostProductFromFeedLink(FeedProductLink link) {
  final pricing = feedPostProductPricing(link);
  return Product(
    id: link.id,
    slug: link.slug,
    title: link.name,
    category: 'Feed',
    brand: 'Natalo',
    imageUrl: link.imageUrl ?? '',
    price: pricing.originalPrice.toDouble(),
    discountPrice:
        (pricing.hasPromo ? pricing.displayPrice : link.discountPrice)
            ?.toDouble(),
    rating: 0,
    reviewCount: 0,
    stock: link.stock,
    weightGram: link.weightGram,
    hasVariants: link.hasVariants,
    description: '',
  );
}

class FeedPostProductSheet extends StatefulWidget {
  final Product product;
  final VoidCallback onOpenProduct;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onBuy;

  const FeedPostProductSheet({
    required this.product,
    required this.onOpenProduct,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  State<FeedPostProductSheet> createState() => _FeedPostProductSheetState();
}

class _FeedPostProductSheetState extends State<FeedPostProductSheet> {
  int _quantity = 1;

  Product get product => widget.product;

  void _decQty() {
    if (_quantity <= 1) return;
    AppHaptics.tap();
    setState(() => _quantity -= 1);
  }

  void _incQty() {
    final maxQty = math.max(1, product.stock);
    if (_quantity >= maxQty) return;
    AppHaptics.tap();
    setState(() => _quantity += 1);
  }

  void _openProduct(BuildContext context) {
    Navigator.pop(context);
    widget.onOpenProduct();
  }

  void _buyNow(BuildContext context) {
    Navigator.pop(context);
    widget.onBuy(_quantity);
  }

  @override
  Widget build(BuildContext context) {
    final discountPercent = product.discountPercent;
    final unavailable = product.stock <= 0;
    return FractionallySizedBox(
      heightFactor: product.hasVariants ? 0.48 : 0.58,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProductPreviewImage(url: product.imageUrl),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              _ProductMetaChip(
                                icon: unavailable
                                    ? Icons.block_rounded
                                    : Icons.check_circle_outline_rounded,
                                label:
                                    unavailable ? 'Tidak tersedia' : 'Tersedia',
                              ),
                              if (product.hasVariants)
                                const _ProductMetaChip(
                                  icon: Icons.tune_rounded,
                                  label: 'Pilih varian',
                                ),
                              if (discountPercent != null)
                                _ProductMetaChip(
                                  icon: Icons.local_offer_outlined,
                                  label: 'Promo $discountPercent%',
                                  gold: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatRupiah(product.finalPrice),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    if (product.hasDiscount) ...[
                      const SizedBox(width: 9),
                      Text(
                        formatRupiah(product.price),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  product.brand.isEmpty ? product.category : product.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!unavailable && !product.hasVariants) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'Jumlah',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _FeedProductQtyStepper(
                        quantity: _quantity,
                        maxQuantity: math.max(1, product.stock),
                        onMinus: _decQty,
                        onPlus: _incQty,
                      ),
                      const Spacer(),
                      Text(
                        'Total ${formatRupiah(product.finalPrice * _quantity)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (product.hasVariants)
                  SizedBox(
                    width: double.infinity,
                    child: _FeedPrimaryProductButton(
                      label: 'Pilih Varian',
                      enabled: !unavailable,
                      onPressed: () => _openProduct(context),
                    ),
                  )
                else
                  Row(
                    children: [
                      _FeedSmallCartButton(
                        enabled: !unavailable,
                        onPressed: () => widget.onAdd(_quantity),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FeedPrimaryProductButton(
                          label: 'Beli Sekarang',
                          enabled: !unavailable,
                          onPressed: () => _buyNow(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 45,
                        width: 45,
                        child: IconButton(
                          onPressed: () => _openProduct(context),
                          tooltip: 'Detail produk',
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPreviewImage extends StatelessWidget {
  final String url;

  const _ProductPreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 92,
        width: 92,
        child: url.isEmpty
            ? const ColoredBox(
                color: Color(0xFF171B22),
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: Colors.white70,
                ),
              )
            : url.startsWith('assets/')
                ? Image.asset(url, fit: BoxFit.cover)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF171B22),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white70,
                      ),
                    ),
                  ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: image,
    );
  }
}

class _ProductMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gold;

  const _ProductMetaChip({
    required this.icon,
    required this.label,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = gold ? feedPostGoldColor : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: gold ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: gold ? 0.35 : 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// End-of-video product CTA — card prominent yang muncul slide-up dari bawah
/// di ~2.5 detik terakhir tiap loop video. Lebih besar + lebih visible dari
/// `product chip kecil` di bottom info biar user yang nonton sampai abis lihat
/// reminder produk dengan tombol "Beli" jelas. Hidden saat long-press
/// preview atau comment sheet open. Dismissable via X icon (sticky sampai
/// user swipe ke post lain).
/// Popup preview produk — auto-show ~2s sebelum video berakhir (logic
/// trigger di feed_screen line 1847). Layout Final Lock Spec:
///  - Dark glass card dengan arrow pointing down ke pill
///  - Thumbnail produk (kiri, 4:5 portrait)
///  - Content right: nama + badges (Diskon merah)
///    + rating (★ 4.9 · 73,6 rb+ terjual) + harga (coret + display merah)
///    + bottom row: cart icon biru + tombol Beli biru
///  - Small X dismiss di kanan atas
