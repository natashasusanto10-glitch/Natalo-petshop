import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../utils/formatters.dart';
import '../../../utils/mention_text.dart';

// Duplikat dari `_officialGold` di feed_screen.dart (tetap dipakai di
// tempat lain di sana) — sama persis nilainya supaya visual identik.
const _officialGold = Color(0xFFF4D47C);
// Duplikat dari `_feedBlue` di feed_screen.dart — setelah ekstraksi ini
// jadi satu-satunya pemakai gradient avatar fallback.
const _feedBlue = Color(0xFF0B7FEA);

/// State chip Ikuti di baris identitas kreator feed.
enum FeedFollowChipState { none, following, hidden }

/// Baris identitas kreator: avatar 34 + nama 13.5 w600 (+verified gold
/// bila official) + chip Ikuti/Mengikuti. Ekstraksi 1:1 dari feed_screen.
class FeedCreatorIdentity extends StatelessWidget {
  final String name;
  final String avatarInitial;
  final String? avatarUrl;
  final bool isOfficial;
  final FeedFollowChipState followState;
  final VoidCallback? onFollowTap;
  final VoidCallback? onProfileTap;

  const FeedCreatorIdentity({
    super.key,
    required this.name,
    required this.avatarInitial,
    this.avatarUrl,
    this.isOfficial = false,
    this.followState = FeedFollowChipState.hidden,
    this.onFollowTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _FeedCreatorAvatar(
          name: avatarInitial,
          profilePhotoUrl: avatarUrl,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isOfficial ? _officialGold : Colors.white,
              // Setipis IG Reels: 13.5 + w600 (dari 15.5/w800) — nama lebih
              // halus, tidak mendominasi over video.
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
        if (isOfficial) ...[
          const SizedBox(width: 6),
          const Icon(
            Icons.verified_rounded,
            color: _officialGold,
            size: 17,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 5,
              ),
            ],
          ),
        ],
        // Chip Ikuti/Mengikuti ala IG — di samping nama. Caller sudah
        // resolve exclusion (official account / self) jadi `hidden`.
        if (followState != FeedFollowChipState.hidden) ...[
          const SizedBox(width: 10),
          _FeedFollowChip(state: followState, onTap: onFollowTap),
        ],
      ],
    );
    if (onProfileTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onProfileTap,
      child: row,
    );
  }
}

/// Chip Ikuti/Mengikuti di samping nama kreator — IG Reels parity: pill
/// transparan + border putih tipis, teks kecil bold. Murni presentasional;
/// state (none/following/hidden) & aksi tap disuplai pemanggil.
class _FeedFollowChip extends StatelessWidget {
  final FeedFollowChipState state;
  final VoidCallback? onTap;

  const _FeedFollowChip({required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (state == FeedFollowChipState.hidden) return const SizedBox.shrink();
    final following = state == FeedFollowChipState.following;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          // Transparan ala IG — cuma border, konten video tembus.
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: following ? 0.38 : 0.85,
            ),
            width: 1,
          ),
        ),
        child: Text(
          following ? 'Mengikuti' : 'Ikuti',
          style: TextStyle(
            color: following ? Colors.white70 : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1,
            shadows: const [
              Shadow(color: Colors.black45, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedCreatorAvatar extends StatelessWidget {
  final String name;
  final String? profilePhotoUrl;

  const _FeedCreatorAvatar({
    required this.name,
    required this.profilePhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = profilePhotoUrl?.trim();
    final hasPhoto = url != null && url.isNotEmpty;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.88),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => _AvatarFallback(name: name),
                errorWidget: (_, __, ___) => _AvatarFallback(name: name),
              )
            : _AvatarFallback(name: name),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;

  const _AvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? 'N' : trimmed[0].toUpperCase();
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _feedBlue.withValues(alpha: 0.92),
            const Color(0xFF38BDF8).withValues(alpha: 0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Caption expandable feed: 13.2 w600 putih, 2 baris + "selengkapnya".
/// Ekstraksi 1:1 dari feed_screen — bedanya expand/collapse kini dikelola
/// sendiri oleh widget (dulu di-lift ke State parent karena tidak ada
/// alasan lain memakainya di luar caption ini).
class FeedExpandableCaption extends StatefulWidget {
  final String text;
  final void Function(String username)? onMentionTap;

  /// Waktu posting — bila diisi, saat expanded tampil timestamp relatif
  /// ("2 hari lalu") di bawah caption, ala IG.
  final DateTime? createdAt;

  /// Controlled mode: bila non-null, state expand dikelola parent (supaya
  /// parent bisa fade scrim + pill produk serempak, dan menutup lewat tap
  /// area video). Bila null, widget kelola sendiri (back-compat pemakai
  /// lama, mis. layar preview posting).
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;

  const FeedExpandableCaption({
    super.key,
    required this.text,
    this.onMentionTap,
    this.createdAt,
    this.expanded,
    this.onExpandedChanged,
  });

  @override
  State<FeedExpandableCaption> createState() => _FeedExpandableCaptionState();
}

class _FeedExpandableCaptionState extends State<FeedExpandableCaption> {
  final List<TapGestureRecognizer> _recognizers = [];
  final ScrollController _scrollController = ScrollController();
  bool _internalExpanded = false;

  bool get _expanded => widget.expanded ?? _internalExpanded;

  // Fade tepi HANYA ke arah yang masih bisa di-scroll: caption pendek (tak
  // scroll) tidak diredupkan, dan tidak ada sinyal palsu "masih ada teks".
  bool _canScrollUp = false;
  bool _canScrollDown = false;

  /// Tarik-turun melewati batas atas scroll caption (jari masih di layar)
  /// menutup panel — konsisten dengan gesture tarik-tutup viewer video.
  static const double _dismissOverscroll = 48;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_recomputeFade);
  }

  @override
  void didUpdateWidget(covariant FeedExpandableCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Controlled mode: parent menutup panel (mis. tap scrim) tanpa lewat
    // _setExpanded — reset posisi baca di sini supaya buka berikutnya
    // mulai dari atas (jalur tap-scrim/komentar/swipe konsisten dengan
    // "lebih sedikit"/overscroll). Aman: masih attached sebelum rebuild
    // collapse melepas scroll view.
    if (oldWidget.expanded == true &&
        widget.expanded == false &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _recomputeFade() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    final up = p.pixels > p.minScrollExtent + 0.5;
    final down = p.pixels < p.maxScrollExtent - 0.5;
    if (up != _canScrollUp || down != _canScrollDown) {
      setState(() {
        _canScrollUp = up;
        _canScrollDown = down;
      });
    }
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    if (widget.expanded == null) {
      setState(() => _internalExpanded = value);
    }
    widget.onExpandedChanged?.call(value);
    if (!value && _scrollController.hasClients) {
      // Reset posisi baca supaya buka berikutnya mulai dari atas.
      _scrollController.jumpTo(0);
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        notification.metrics.pixels <
            notification.metrics.minScrollExtent - _dismissOverscroll) {
      _setExpanded(false);
    }
    return false;
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    _scrollController.removeListener(_recomputeFade);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.isEmpty) return const SizedBox.shrink();
    const limit = 90;
    final isLong = text.length > limit;
    final expanded = _expanded && isLong;
    final visible = expanded || !isLong
        ? text
        : '${text.substring(0, limit).trimRight()}... ';

    // Dispose recognizers lama tiap rebuild — fresh per render.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 13.2,
      fontWeight: FontWeight.w600,
      height: 1.38,
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    const mentionStyle = TextStyle(
      color: Color(0xFF60A5FA),
      fontSize: 13.2,
      fontWeight: FontWeight.w900,
      height: 1.38,
      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
    );

    final mentionSpans = buildMentionSpans(
      visible,
      onMentionTap: (handle) => widget.onMentionTap?.call(handle),
      defaultStyle: baseStyle,
      mentionStyle: mentionStyle,
      collectRecognizers: _recognizers,
    );

    final richText = Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          ...mentionSpans,
          if (isLong)
            TextSpan(
              text: expanded ? '  lebih sedikit' : 'selengkapnya',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12.8,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
      maxLines: expanded ? null : 2,
      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
    );

    Widget body;
    if (!expanded) {
      body = richText;
    } else {
      // Panel baca ala IG: tinggi maks ~45% layar, isi ter-scroll dengan
      // fade mask tepi (HANYA ke arah yang masih bisa di-scroll), timestamp
      // relatif di bawah. Author di parent tetap pinned di atas panel ini.
      final maxPanelHeight = MediaQuery.sizeOf(context).height * 0.45;
      // Recompute flag fade setelah layout — metrics scroll baru diketahui
      // pasca-frame (content bisa lebih pendek dari panel = tak scroll).
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeFade());
      // Fade hanya di tepi yang punya konten tersembunyi ke arah itu:
      // caption pendek → tanpa fade; di atas → hanya fade bawah; mentok
      // bawah → hanya fade atas.
      final topStop = _canScrollUp ? 0.045 : 0.0;
      final bottomStop = _canScrollDown ? 0.955 : 1.0;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPanelHeight),
            child: ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0.0, topStop, bottomStop, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: richText,
                ),
              ),
            ),
          ),
          if (widget.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                formatRelativeTime(widget.createdAt!),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      onTap: isLong ? () => _setExpanded(!expanded) : null,
      // AnimatedSize: caption tidak snap buka/tutup — tinggi mengembang
      // halus, dan karena bottom info di-anchor ke bawah (Positioned.bottom),
      // nama kreator di atasnya ikut terangkat pelan sebagai satu gerakan.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        reverseDuration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        // topLeft: baris awal tetap terlihat (terangkat naik), baris baru
        // tersingkap di bawahnya — terasa "membuka", bukan konten loncat.
        alignment: Alignment.topLeft,
        child: body,
      ),
    );
  }
}
