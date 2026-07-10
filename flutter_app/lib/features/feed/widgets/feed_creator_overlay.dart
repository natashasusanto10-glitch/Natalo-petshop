import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

  const FeedExpandableCaption({super.key, required this.text, this.onMentionTap});

  @override
  State<FeedExpandableCaption> createState() => _FeedExpandableCaptionState();
}

class _FeedExpandableCaptionState extends State<FeedExpandableCaption> {
  final List<TapGestureRecognizer> _recognizers = [];
  bool _expanded = false;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.isEmpty) return const SizedBox.shrink();
    const limit = 90;
    final isLong = text.length > limit;
    final visible = _expanded || !isLong
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

    return GestureDetector(
      onTap: isLong ? () => setState(() => _expanded = !_expanded) : null,
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            ...mentionSpans,
            if (isLong)
              TextSpan(
                text: _expanded ? '  lebih sedikit' : 'selengkapnya',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
    );
  }
}
