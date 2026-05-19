import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import 'app_toast.dart';
import 'natalo_paw_refresh_indicator.dart';

/// Comment sheet style Instagram Reels — 1:1 visual:
///
/// Layout:
/// - Drag handle bar di atas (sudah expose [onDragUpdate]/[onDragEnd]
///   untuk feed_screen.dart untuk drive video shrink + dismiss gesture)
/// - Header: "X komentar" + close button
/// - List komentar:
///   * Parent: avatar + name + content + meta (waktu, like, balas)
///   * Reply: indented 44px, smaller avatar, sama meta
/// - Bottom input bar:
///   * Reply banner ("Membalas @username • Batal") kalau lagi reply mode
///   * Avatar user current + TextField + send button
///
/// API:
/// - GET /api/feed/posts/:postId/comments?cursor= → list newest-first
/// - POST /api/feed/posts/:postId/comments → {content, parentCommentId?}
/// - POST/DELETE /api/feed/comments/:commentId/like → toggle like
class FeedCommentSheet extends StatefulWidget {
  /// Height factor default saat sheet pertama buka — match Reels: ~56%.
  static const double reelsHeightFactor = 0.56;

  final FeedPost post;
  final bool applyKeyboardInset;
  final ScrollController? sheetScrollController;
  final VoidCallback? onClose;

  /// Callback ke feed_screen kalau jumlah komentar bertambah (untuk
  /// update counter di action rail saat sheet tutup).
  final ValueChanged<int>? onAddedCountChanged;

  /// Drag handle area gesture — diteruskan ke feed_screen untuk
  /// dismiss saat user drag handle ke bawah.
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final ValueChanged<DragEndDetails>? onDragEnd;

  const FeedCommentSheet({
    super.key,
    required this.post,
    this.applyKeyboardInset = true,
    this.sheetScrollController,
    this.onClose,
    this.onAddedCountChanged,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  State<FeedCommentSheet> createState() => _FeedCommentSheetState();
}

class _FeedCommentSheetState extends State<FeedCommentSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  List<FeedComment> _comments = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _posting = false;
  String? _error;

  /// Reply mode — kalau diisi, comment yang sedang dipost akan jadi
  /// reply ke comment ini.
  FeedComment? _replyTarget;

  /// Jumlah komentar baru di-add lewat sheet ini (untuk update counter
  /// post saat sheet tutup).
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    widget.sheetScrollController?.addListener(_handleScroll);
  }

  @override
  void dispose() {
    widget.sheetScrollController?.removeListener(_handleScroll);
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final ctrl = widget.sheetScrollController;
    if (ctrl == null || !ctrl.hasClients) return;
    // Trigger load-more saat scroll dekat bottom (200px buffer).
    if (ctrl.position.pixels >= ctrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await feedService.fetchComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.statusCode == 401
            ? 'Login untuk lihat komentar.'
            : 'Gagal memuat komentar. Tarik untuk coba lagi.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memuat komentar. Tarik untuk coba lagi.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await feedService.fetchComments(
        widget.post.id,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.items];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    await _loadInitial();
  }

  void _setReplyTarget(FeedComment? target) {
    setState(() => _replyTarget = target);
    if (target != null) {
      // Kasih hint @username di input supaya feel native instagram.
      final mention = target.author.username ?? target.author.name;
      if (!_inputCtrl.text.startsWith('@$mention')) {
        _inputCtrl.text = '@$mention ';
        _inputCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputCtrl.text.length),
        );
      }
      _inputFocus.requestFocus();
      AppHaptics.tap();
    } else {
      _inputCtrl.clear();
    }
  }

  Future<void> _postComment() async {
    final raw = _inputCtrl.text.trim();
    if (raw.isEmpty || _posting) return;
    if (!memberStore.isLoggedIn) {
      Navigator.pushNamed(context, '/member/login');
      return;
    }

    setState(() => _posting = true);
    AppHaptics.tap();

    try {
      final content = raw;
      final parentId = _replyTarget?.id;
      final created = await feedService.postComment(
        widget.post.id,
        content: content,
        parentCommentId: parentId,
      );
      if (!mounted) return;
      // Insert: kalau reply, sisipkan tepat setelah parent + replies
      // existing. Kalau parent, prepend di top (newest-first).
      setState(() {
        if (parentId != null) {
          final parentIndex =
              _comments.indexWhere((c) => c.id == parentId);
          if (parentIndex >= 0) {
            // Cari insertion point: setelah parent + semua reply existing.
            int insertAt = parentIndex + 1;
            while (insertAt < _comments.length &&
                _comments[insertAt].parentCommentId == parentId) {
              insertAt++;
            }
            _comments = [
              ..._comments.sublist(0, insertAt),
              created,
              ..._comments.sublist(insertAt),
            ];
          } else {
            _comments = [created, ..._comments];
          }
        } else {
          _comments = [created, ..._comments];
        }
        _addedCount += 1;
        _posting = false;
        _replyTarget = null;
        _inputCtrl.clear();
      });
      widget.onAddedCountChanged?.call(_addedCount);
      AppHaptics.success();
      _inputFocus.unfocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      if (e.statusCode == 401) {
        Navigator.pushNamed(context, '/member/login');
      } else {
        AppToast.show(
          context,
          e.message.isNotEmpty ? e.message : 'Komentar belum terkirim.',
          kind: ToastKind.warning,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      AppToast.show(
        context,
        'Komentar belum terkirim. Coba lagi.',
        kind: ToastKind.warning,
      );
    }
  }

  Future<void> _toggleLike(FeedComment comment) async {
    if (!memberStore.isLoggedIn) {
      Navigator.pushNamed(context, '/member/login');
      return;
    }
    AppHaptics.tap();
    final wasLiked = comment.viewerLiked;
    final prevCount = comment.likeCount;
    // Optimistic update.
    _updateComment(comment.copyWith(
      viewerLiked: !wasLiked,
      likeCount: wasLiked
          ? (prevCount > 0 ? prevCount - 1 : 0)
          : prevCount + 1,
    ));
    try {
      final newCount = await feedService.toggleCommentLike(
        comment.id,
        currentlyLiked: wasLiked,
      );
      _updateComment(comment.copyWith(
        viewerLiked: !wasLiked,
        likeCount: newCount,
      ));
    } on ApiException catch (e) {
      // Rollback.
      _updateComment(comment);
      if (!mounted) return;
      if (e.statusCode == 401) {
        Navigator.pushNamed(context, '/member/login');
      } else {
        AppToast.show(
          context,
          'Like belum berhasil.',
          kind: ToastKind.warning,
        );
      }
    } catch (_) {
      _updateComment(comment);
    }
  }

  void _updateComment(FeedComment updated) {
    if (!mounted) return;
    final index = _comments.indexWhere((c) => c.id == updated.id);
    if (index < 0) return;
    setState(() {
      final copy = [..._comments];
      copy[index] = updated;
      _comments = copy;
    });
  }

  /// Group comments: parents first (newest-first), each followed by
  /// chronological replies. Server bisa return flat — kita group sini.
  List<_CommentDisplayItem> _buildDisplayItems() {
    final items = <_CommentDisplayItem>[];
    final replyMap = <String, List<FeedComment>>{};

    for (final c in _comments) {
      if (c.parentCommentId != null) {
        replyMap.putIfAbsent(c.parentCommentId!, () => []).add(c);
      }
    }

    for (final c in _comments) {
      if (c.parentCommentId != null) continue; // skip — render under parent
      items.add(_CommentDisplayItem(comment: c, isReply: false));
      final replies = replyMap[c.id];
      if (replies != null) {
        // Sort replies oldest-first (standard Instagram threading order).
        replies.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        for (final r in replies) {
          items.add(_CommentDisplayItem(comment: r, isReply: true));
        }
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = widget.applyKeyboardInset
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: Container(
        // Dark drawer Instagram Reels-style — bukan putih (user spec).
        // Background, header text, divider, input — semua flip ke variant
        // dark dengan white alpha variants untuk visual hierarchy.
        decoration: BoxDecoration(
          color: const Color(0xFF111417),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
        child: Column(
          children: [
            // ── Drag handle ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: widget.onDragUpdate,
              onVerticalDragEnd: widget.onDragEnd,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _comments.isEmpty
                          ? 'Komentar'
                          : '${_comments.length}${_nextCursor != null ? '+' : ''} komentar',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.70),
                      size: 22,
                    ),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              color: Colors.white.withValues(alpha: 0.08),
            ),

            // ── List comments ──
            Expanded(
              child: _buildListBody(),
            ),

            // ── Reply banner ──
            if (_replyTarget != null) _buildReplyBanner(),

            // ── Input bar ──
            _buildInputBar(keyboardInset),
          ],
        ),
      ),
    );
  }

  Widget _buildListBody() {
    if (_loading && _comments.isEmpty) {
      return const _CommentListSkeleton();
    }
    if (_error != null && _comments.isEmpty) {
      return NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: widget.sheetScrollController,
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
          children: [
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return ListView(
        controller: widget.sheetScrollController,
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 32),
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mode_comment_outlined,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 40,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Belum ada komentar',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jadi yang pertama berkomentar!',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final items = _buildDisplayItems();

    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: widget.sheetScrollController,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NataloColors.primary,
                  ),
                ),
              ),
            );
          }
          final item = items[index];
          return _CommentTile(
            comment: item.comment,
            isReply: item.isReply,
            onLike: () => _toggleLike(item.comment),
            onReply: () => _setReplyTarget(item.comment),
          );
        },
      ),
    );
  }

  Widget _buildReplyBanner() {
    final target = _replyTarget!;
    final name = target.author.username ?? target.author.name;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      decoration: BoxDecoration(
        // Reply banner di atas composer — slightly lighter than drawer
        // bg untuk kasih hint "ini area different state".
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Membalas @$name',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _setReplyTarget(null),
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.65),
            ),
            tooltip: 'Batal balas',
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(double keyboardInset) {
    final profile = memberStore.profile;
    final initial = (profile?.name.isNotEmpty ?? false)
        ? profile!.name.substring(0, 1).toUpperCase()
        : 'N';
    final isLoggedIn = memberStore.isLoggedIn;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111417),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        8,
        10 + keyboardInset,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar user current (initial fallback) — soft blue tile.
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF3FF),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: NataloColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Input field — dark transparent fill, white text + cursor.
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 40,
                  maxHeight: 120,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _inputFocus,
                  enabled: !_posting,
                  maxLines: null,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  cursorColor: Colors.white,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(500),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isLoggedIn
                        ? 'Tambahkan komentar...'
                        : 'Login untuk komentar...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                  onTap: () {
                    if (!isLoggedIn) {
                      Navigator.pushNamed(context, '/member/login');
                    }
                  },
                ),
              ),
            ),

            // Send button (disabled saat kosong / posting).
            _SendButton(
              enabled: !_posting && _inputCtrl.text.trim().isNotEmpty,
              posting: _posting,
              onPressed: _postComment,
            ),
          ],
        ),
      ),
    );
  }
}

/// Item wrapper untuk display — bedakan parent vs reply.
class _CommentDisplayItem {
  final FeedComment comment;
  final bool isReply;
  const _CommentDisplayItem({required this.comment, required this.isReply});
}

/// Single comment row — avatar + name + content + meta + like button.
class _CommentTile extends StatelessWidget {
  final FeedComment comment;
  final bool isReply;
  final VoidCallback onLike;
  final VoidCallback onReply;

  const _CommentTile({
    required this.comment,
    required this.isReply,
    required this.onLike,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    final name = author.username?.isNotEmpty == true
        ? author.username!
        : author.name;
    final avatarUrl = author.profilePhotoUrl ?? author.avatarUrl;
    final initial =
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'N';
    final avatarSize = isReply ? 28.0 : 36.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isReply ? 64 : 20,
        7,
        16,
        7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar.
          _CommentAvatar(
            size: avatarSize,
            initial: initial,
            imageUrl: avatarUrl,
          ),
          const SizedBox(width: 10),

          // Body: name + content + meta.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          // White untuk dark drawer (was 0xFF111111 dark
                          // text di dark bg → poor contrast, terlihat
                          // bluish/faded di screenshot user).
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (author.isOfficial || author.isAdmin) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: NataloColors.primary,
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      _timeAgo(comment.createdAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.content,
                  style: TextStyle(
                    // White alpha 90% — primary content content readable
                    // di dark bg, slightly softer dari 100% white untuk
                    // mengurangi eye strain di long scroll.
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (comment.likeCount > 0) ...[
                      Text(
                        '${_formatCount(comment.likeCount)} suka',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onReply,
                      child: Text(
                        'Balas',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Like heart.
          _CommentLikeButton(
            liked: comment.viewerLiked,
            onTap: onLike,
          ),
        ],
      ),
    );
  }
}

/// Avatar untuk comment row — pakai NetworkImage kalau ada URL, fallback
/// ke initial bubble. Tidak pakai CachedNetworkImage di sini untuk avoid
/// extra dep call — comment list bisa scroll panjang, simpler.
class _CommentAvatar extends StatelessWidget {
  final double size;
  final String initial;
  final String? imageUrl;

  const _CommentAvatar({
    required this.size,
    required this.initial,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty && url.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialBubble(),
        ),
      );
    }
    return _initialBubble();
  }

  Widget _initialBubble() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF3FF),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: NataloColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Heart icon kanan-bottom row comment — toggle dengan scale-bounce.
class _CommentLikeButton extends StatefulWidget {
  final bool liked;
  final VoidCallback onTap;

  const _CommentLikeButton({required this.liked, required this.onTap});

  @override
  State<_CommentLikeButton> createState() => _CommentLikeButtonState();
}

class _CommentLikeButtonState extends State<_CommentLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(
          CurveTween(curve: Curves.easeInOutCubic),
        ),
        weight: 60,
      ),
    ]).animate(_bounceCtrl);
  }

  @override
  void didUpdateWidget(covariant _CommentLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked && widget.liked) {
      _bounceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, top: 4),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              widget.liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              key: ValueKey(widget.liked),
              color: widget.liked
                  ? const Color(0xFFEF4444)
                  // Outline heart pakai white alpha 60% — readable di
                  // dark drawer (was 0xFF8E939B gray = too dim).
                  : Colors.white.withValues(alpha: 0.60),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// Send button — paper plane icon, biru saat enabled, gray saat empty.
/// Spinning saat posting.
class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool posting;
  final VoidCallback onPressed;

  const _SendButton({
    required this.enabled,
    required this.posting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (posting) {
      return const SizedBox(
        width: 44,
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NataloColors.primary,
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 38,
          child: Icon(
            Icons.send_rounded,
            color: enabled
                ? NataloColors.primary
                // Disabled state pakai white alpha 30% — visible di dark
                // bg tapi clearly "inactive" (was 0xFFC4C8CF light gray =
                // hilang di dark drawer).
                : Colors.white.withValues(alpha: 0.30),
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading state — 5 comment placeholder rows dengan shimmer.
class _CommentListSkeleton extends StatelessWidget {
  const _CommentListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 10,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 180,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Format waktu relative ringkas (Instagram-style): "5d", "3j", "2h",
/// "1mg", "5bln", "1th". Bahasa Indonesia singkat.
String _timeAgo(DateTime created) {
  final now = DateTime.now();
  final diff = now.difference(created);
  if (diff.inSeconds < 60) return 'baru';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}j';
  if (diff.inDays < 7) return '${diff.inDays}h';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}mg';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}bln';
  return '${(diff.inDays / 365).floor()}th';
}

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}jt';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}rb';
  return '$n';
}
