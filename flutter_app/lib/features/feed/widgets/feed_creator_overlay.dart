import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/natalo_colors.dart';
import '../../../utils/formatters.dart';
import '../../../utils/mention_text.dart';
import '../../../widgets/official_brand_avatar.dart';
import '../../../widgets/profile_avatar.dart';

// Emas identitas official — kini satu sumber di NataloColors.officialGold
// (dipakai seragam di semua layar). Alias lokal supaya diff minimal.
const _officialGold = NataloColors.officialGold;

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
          isOfficial: isOfficial,
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
          const OfficialVerifiedBadge(size: 17),
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
  final bool isOfficial;

  const _FeedCreatorAvatar({
    required this.name,
    required this.profilePhotoUrl,
    this.isOfficial = false,
  });

  @override
  Widget build(BuildContext context) {
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
      child: ProfileAvatar(
        initial: name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase(),
        imageUrl: profilePhotoUrl,
        size: 34,
        fontSize: 14,
        isOfficial: isOfficial,
        plain: true,
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

  // w400 (bukan w600) — isi caption ala IG: username tebal, badan teks
  // normal. w600 di seluruh caption bikin blok teks terasa "berteriak".
  static const _baseStyle = TextStyle(
    color: Colors.white,
    fontSize: 13.2,
    fontWeight: FontWeight.w400,
    height: 1.38,
    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
  );
  static const _mentionStyle = TextStyle(
    color: Color(0xFF60A5FA),
    fontSize: 13.2,
    fontWeight: FontWeight.w900,
    height: 1.38,
    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
  );
  static const _maxCollapsedLines = 2;

  /// Ukur apakah `text` (spans-nya) melebihi 2 baris pada `maxWidth`.
  /// Basis-baris ter-render — bukan jumlah karakter — supaya caption pendek
  /// yang tetap wrap >2 baris di kolom sempit ikut terdeteksi "panjang".
  bool _exceedsCollapsed(String text, double maxWidth, TextScaler scaler) {
    final tp = _paint(_measureSpans(text), maxWidth, scaler);
    final exceeded = tp.didExceedMaxLines;
    tp.dispose();
    return exceeded;
  }

  /// Cari panjang prefix terpanjang dari `text` yang, digabung dengan
  /// "…  selengkapnya", masih muat dalam 2 baris pada `maxWidth`. Menjamin
  /// affordance "selengkapnya" selalu terlihat (tak terdorong ke baris ke-3
  /// lalu ter-ellipsis hilang).
  int _fitCollapsedLength(String text, double maxWidth, TextScaler scaler) {
    var lo = 0;
    var hi = text.length;
    var best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final candidate = '${text.substring(0, mid).trimRight()}…  selengkapnya';
      final tp = _paint(_measureSpans(candidate), maxWidth, scaler);
      final fits = !tp.didExceedMaxLines;
      tp.dispose();
      if (fits) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  /// Spans khusus pengukuran — recognizer throwaway langsung di-dispose,
  /// karena TextPainter cuma butuh geometri (recognizer tak memengaruhi
  /// layout). Weight mention (w900) dipertahankan agar lebar akurat.
  List<InlineSpan> _measureSpans(String text) {
    final throwaway = <TapGestureRecognizer>[];
    final spans = buildMentionSpans(
      text,
      onMentionTap: (_) {},
      defaultStyle: _baseStyle,
      mentionStyle: _mentionStyle,
      collectRecognizers: throwaway,
    );
    for (final r in throwaway) {
      r.dispose();
    }
    return spans;
  }

  TextPainter _paint(
      List<InlineSpan> spans, double maxWidth, TextScaler scaler) {
    return TextPainter(
      text: TextSpan(style: _baseStyle, children: spans),
      maxLines: _maxCollapsedLines,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // Deteksi overflow berbasis baris ter-render, bukan jumlah karakter.
        final isLong =
            maxWidth.isFinite && _exceedsCollapsed(text, maxWidth, scaler);
        final expanded = _expanded && isLong;
        final visible = expanded || !isLong
            ? text
            : '${text.substring(0, _fitCollapsedLength(text, maxWidth, scaler)).trimRight()}…  ';

        // Dispose recognizers lama tiap rebuild — fresh per render.
        for (final r in _recognizers) {
          r.dispose();
        }
        _recognizers.clear();

        final mentionSpans = buildMentionSpans(
          visible,
          onMentionTap: (handle) => widget.onMentionTap?.call(handle),
          defaultStyle: _baseStyle,
          mentionStyle: _mentionStyle,
          collectRecognizers: _recognizers,
        );

        final richText = Text.rich(
          TextSpan(
            style: _baseStyle,
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
          maxLines: expanded ? null : _maxCollapsedLines,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        );

        Widget body;
        if (!expanded) {
          body = richText;
        } else {
          // Panel baca ala IG: tinggi maks ~45% layar, isi ter-scroll dengan
          // fade mask tepi (HANYA ke arah yang masih bisa di-scroll),
          // timestamp relatif di bawah. Author di parent tetap pinned.
          final maxPanelHeight = MediaQuery.sizeOf(context).height * 0.45;
          // Recompute flag fade setelah layout — metrics scroll baru
          // diketahui pasca-frame (content bisa lebih pendek dari panel).
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
          // halus; nama kreator di atasnya ikut terangkat sebagai satu
          // gerakan.
          child: AnimatedSize(
            duration: const Duration(milliseconds: 320),
            reverseDuration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: body,
          ),
        );
      },
    );
  }
}
