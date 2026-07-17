import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../theme/natalo_text.dart';
import '../../../models/product.dart';
import '../../../services/follow_service.dart';
import '../../../state/follow_override_store.dart';
import '../../../state/member_store.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/official_brand_avatar.dart';
import '../../../widgets/post_likers_sheet.dart';
import 'feed_action_rail.dart';
import 'feed_creator_overlay.dart';
import 'feed_product_pill.dart';

/// Public/shared widgets used by BOTH `_PhotoCarouselPostView` (in
/// `feed_screen.dart`) and `FeedVideoPostView`
/// (`feed_video_post_view.dart`). Extracted here to keep exactly one
/// implementation and avoid visual drift between the photo and video
/// call sites, without creating a circular import between those two
/// files.

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
                      style: const TextStyle(fontWeight: NataloWeight.strong),
                    ),
                    if (others > 0) ...[
                      const TextSpan(text: ' dan '),
                      TextSpan(
                        text: '$others orang lainnya',
                        style: const TextStyle(fontWeight: NataloWeight.strong),
                      ),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: NataloWeight.onMedia,
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
                style: const TextStyle(fontSize: 10, fontWeight: NataloWeight.strong),
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
