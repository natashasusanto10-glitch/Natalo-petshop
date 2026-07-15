import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:video_player/video_player.dart';

import '../models/feed_create_post_draft.dart';
import '../models/feed_post.dart';
import '../features/feed/video/post_video_warm_handoff.dart';
import '../services/feed_service.dart';
import '../services/video_quality_service.dart';
import '../state/feed_draft_store.dart';
import '../state/feed_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import 'feed_media_picker_screen.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_avatar.dart';
import 'feed_new_post_screen.dart';
import 'member_post_detail_screen.dart';

const _brandBlue = NataloColors.primary;

class MemberPostsScreen extends StatefulWidget {
  const MemberPostsScreen({super.key});

  @override
  State<MemberPostsScreen> createState() => _MemberPostsScreenState();
}

class _MemberPostsScreenState extends State<MemberPostsScreen> {
  final _scrollController = ScrollController();
  int _filterIndex = 0;
  List<FeedDraft> _drafts = const [];
  List<FeedPost> _allPosts = const [];
  bool _loading = true;
  bool _openingPost = false;
  // Pagination state:
  // - _nextCursor: post id terakhir dari fetch sebelumnya. null = end-of-list.
  // - _loadingMore: guard supaya scroll listener tidak fire concurrent fetch.
  // - _initialLoadDone: tahu kapan boleh trigger load-more (skip saat initial).
  String? _nextCursor;
  bool _loadingMore = false;
  bool _initialLoadDone = false;
  String? _preparedPostId;
  PostVideoWarmHandoff? _preparedHandoff;

  static const _filters = [
    _PostsFilter(
      label: 'Semua',
      type: _PostFilterType.all,
    ),
    _PostsFilter(
      label: 'Foto',
      type: _PostFilterType.photo,
    ),
    _PostsFilter(
      label: 'Video',
      type: _PostFilterType.video,
    ),
    _PostsFilter(
      label: 'Menunggu',
      type: _PostFilterType.review,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollLoadMore);
    _loadPosts();
    _loadDrafts();
  }

  @override
  void dispose() {
    unawaited(_preparedHandoff?.disposeIfUnclaimed());
    _scrollController
      ..removeListener(_handleScrollLoadMore)
      ..dispose();
    super.dispose();
  }

  PostVideoWarmHandoff? _createWarmHandoff(FeedPost post) {
    return PostVideoWarmHandoff.createIfVideo(
      isVideo: post.isVideo,
      postId: post.id,
      url: videoQualityService.resolvePlaybackUrl(
        post.videoPlaybackUrl,
        dataSaverUrl: post.videoDataSaverUrl,
        userPreference: appSettingsStore.feedVideoQuality,
      ),
    );
  }

  void _preparePostVideo(FeedPost post) {
    if (_openingPost || !post.isVideo || _preparedPostId == post.id) return;
    final stale = _preparedHandoff;
    _preparedHandoff = _createWarmHandoff(post);
    _preparedPostId = _preparedHandoff == null ? null : post.id;
    unawaited(stale?.disposeIfUnclaimed());
  }

  void _cancelPreparedPost([String? postId]) {
    if (postId != null && _preparedPostId != postId) return;
    final stale = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    unawaited(stale?.disposeIfUnclaimed());
  }

  PostVideoWarmHandoff? _takePreparedPost(FeedPost post) {
    if (_preparedPostId != post.id) {
      _cancelPreparedPost();
      return null;
    }
    final handoff = _preparedHandoff;
    _preparedHandoff = null;
    _preparedPostId = null;
    return handoff;
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _initialLoadDone = false;
      _nextCursor = null;
    });
    final fetchedAt = DateTime.now();
    try {
      final page = await feedService.fetchMyPosts(filter: 'all');
      if (!mounted) return;
      // Seed FeedStore — supaya cross-screen sync (Reels → grid count
      // refresh, Detail → grid count refresh) kalau di masa depan grid
      // tile expose count. Sekaligus protect dari stale overwrite via
      // fetchedAt.
      feedStore.mergeFromServer(
        page.items,
        fetchedAt: fetchedAt,
      );
      setState(() {
        _allPosts = page.items;
        _nextCursor = page.nextCursor;
        _loading = false;
        _initialLoadDone = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allPosts = const [];
        _nextCursor = null;
        _loading = false;
        _initialLoadDone = true;
      });
    }
  }

  /// Lazy-load next page saat scroll near bottom. Trigger ~400px sebelum
  /// end supaya user tidak ngerasa "loading hits hard" — page baru udah
  /// stand-by saat user mau scroll lebih jauh.
  void _handleScrollLoadMore() {
    if (!_initialLoadDone || _loadingMore || _nextCursor == null) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    final fetchedAt = DateTime.now();
    try {
      final page = await feedService.fetchMyPosts(
        filter: 'all',
        cursor: _nextCursor,
      );
      if (!mounted) return;
      feedStore.mergeFromServer(
        page.items,
        fetchedAt: fetchedAt,
      );
      setState(() {
        // Append + dedupe by id (defensive: backend cursor pattern
        // sudah skip:1 tapi tetap guard kalau ada race condition).
        final existingIds = _allPosts.map((p) => p.id).toSet();
        final fresh =
            page.items.where((p) => !existingIds.contains(p.id)).toList();
        _allPosts = [..._allPosts, ...fresh];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadDrafts() async {
    try {
      final drafts = await feedDraftStore.load();
      if (!mounted) return;
      setState(() => _drafts = drafts);
    } catch (_) {
      if (!mounted) return;
      setState(() => _drafts = const []);
    }
  }

  List<FeedPost> get _visiblePosts {
    final filter = _filters[_filterIndex].type;
    return _allPosts.where((post) {
      return switch (filter) {
        _PostFilterType.all => true,
        _PostFilterType.photo => !post.isVideo,
        _PostFilterType.video => post.isVideo,
        _PostFilterType.review => post.statusInfo == FeedPostStatus.pending,
      };
    }).toList();
  }

  Future<void> _openUpload() async {
    AppHaptics.tap();
    final uploaded = await FeedMediaPickerScreen.open(context);
    if (uploaded == true) {
      await _loadPosts();
    }
    await _loadDrafts();
  }

  /// Tap kartu draft sehat → rekonstruksi editor state + push
  /// `FeedNewPostScreen` dengan `resumeDraftId` supaya save berikutnya
  /// upsert (bukan duplikat). Setelah kembali (publish sukses / save
  /// ulang / batal), reload daftar draft + postingan supaya grid & rail
  /// sinkron.
  Future<void> _openDraft(FeedDraft draft) async {
    if (draft.broken) {
      await _confirmDeleteDraft(draft);
      return;
    }
    AppHaptics.tap();
    if (draft.type == 'video') {
      await _restoreVideoDraft(draft);
    } else {
      await _restorePhotoDraft(draft);
    }
    await _loadPosts();
    await _loadDrafts();
  }

  Future<void> _restorePhotoDraft(FeedDraft draft) async {
    final files = <File>[];
    for (final path in draft.mediaPaths) {
      final file = File(path);
      if (await file.exists()) files.add(file);
    }
    if (files.isEmpty || !mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.photos(files),
          prefilledCaption: draft.caption,
          prefilledProductIds: draft.productIds,
          resumeDraftId: draft.id,
        ),
      ),
    );
  }

  /// Rekonstruksi `FeedCreatePostDraft` dari `FeedDraft` tersimpan —
  /// menutup skip hardcoded video draft (dulu langsung `return false` di
  /// _tryRestoreComposerDraft). `originalDurationMs`/`trimmedDurationMs`
  /// disimpan sejak `_saveDraftAndExit` (feed_new_post_screen.dart) supaya
  /// validasi durasi 1..60s + trim guard di `_upload` tetap jalan.
  Future<void> _restoreVideoDraft(FeedDraft draft) async {
    if (draft.mediaPaths.isEmpty) return;
    final videoPath = draft.mediaPaths.first;
    if (!await File(videoPath).exists() || !mounted) return;
    final originalMs = draft.originalDurationMs;
    final reconstructed = FeedCreatePostDraft(
      localVideoPath: videoPath,
      thumbnailPath: draft.thumbnailPath,
      originalDuration:
          originalMs != null ? Duration(milliseconds: originalMs) : null,
      trimmedDuration: draft.trimmedDurationMs != null
          ? Duration(milliseconds: draft.trimmedDurationMs!)
          : null,
      trimStart: draft.trimStartMs != null
          ? Duration(milliseconds: draft.trimStartMs!)
          : null,
      caption: draft.caption,
      taggedProductIds: draft.productIds,
      userPickedCover: draft.userPickedCover,
    );
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FeedNewPostScreen(
          draft: NewPostMediaDraft.video(reconstructed),
          prefilledCaption: draft.caption,
          prefilledProductIds: draft.productIds,
          resumeDraftId: draft.id,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDraft(FeedDraft draft) async {
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus draft?'),
        content: Text(
          draft.broken
              ? 'Media draft ini sudah tidak ditemukan di perangkat. Hapus draft ini?'
              : 'Draft yang dihapus tidak bisa dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await feedDraftStore.remove(draft.id);
    await _loadDrafts();
  }

  void _onFilterChanged(int index) {
    AppHaptics.tap();
    setState(() => _filterIndex = index);
  }

  Future<void> _openPostDetail(List<FeedPost> posts, int initialIndex) async {
    if (_openingPost) return;
    _openingPost = true;
    AppHaptics.tap();
    final post = posts[initialIndex];
    final handoff = _takePreparedPost(post) ?? _createWarmHandoff(post);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => MemberPostDetailScreen(
            post: post,
            posts: posts,
            initialIndex: initialIndex,
            authorIsOfficial: memberStore.profile?.isAdmin ?? false,
            warmVideoHandoff: handoff,
            initialNextCursor: _nextCursor,
            loadMoreScopedPosts: (cursor) => feedService.fetchMyPosts(
              filter: 'all',
              cursor: cursor,
            ),
          ),
        ),
      );
    } finally {
      await handoff?.disposeIfUnclaimed();
      _openingPost = false;
    }
    if (mounted) await _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    final visiblePosts = _visiblePosts;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Postingan Saya',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openUpload,
            tooltip: 'Buat postingan',
            icon: Icon(
              Icons.add_rounded,
              color: cs.onSurface,
              size: 32,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: NataloPawRefreshIndicator(
        onRefresh: () async {
          await _loadPosts();
          await _loadDrafts();
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _NlFeedIntro(),
                    if (_drafts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DraftSection(
                        drafts: _drafts,
                        onTap: _openDraft,
                        onDelete: _confirmDeleteDraft,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _FeedGalleryTabs(
                filters: _filters,
                activeIndex: _filterIndex,
                onTap: _onFilterChanged,
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_allPosts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: _EmptyPostsCard(onUpload: _openUpload),
                ),
              )
            else if (visiblePosts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 32),
                  child: _FilteredEmptyState(
                    label: _filters[_filterIndex].label,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 28),
                sliver: SliverGrid.builder(
                  itemCount: visiblePosts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final post = visiblePosts[index];
                    return _GalleryPostTile(
                      post: post,
                      onTap: () => _openPostDetail(visiblePosts, index),
                      onTapDown: () => _preparePostVideo(post),
                      onTapCancel: () => _cancelPreparedPost(post.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PostFilterType { all, photo, video, review }

class _PostsFilter {
  final String label;
  final _PostFilterType type;

  const _PostsFilter({
    required this.label,
    required this.type,
  });
}

class _NlFeedIntro extends StatelessWidget {
  const _NlFeedIntro();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        final profile = memberStore.profile;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ProfileAvatar(
              initial: profile?.initial ?? 'N',
              imageUrl: profile?.profilePhotoUrl,
              size: 50,
              fontSize: 20,
              isOfficial: profile?.isAdmin ?? false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Cerita lucu, gemas, dan seru kamu kumpul di sini. 🐾💙',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 15.5,
                  height: 1.36,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bagian "Draft" — header kecil + rail horizontal kartu draft. Muncul
/// kalau `FeedDraftStore` punya ≥1 entry (maks 5, terlama tergeser di
/// store). Setiap kartu 72×96 (thumbnail) + label tipe/umur di bawah.
class _DraftSection extends StatelessWidget {
  final List<FeedDraft> drafts;
  final ValueChanged<FeedDraft> onTap;
  final ValueChanged<FeedDraft> onDelete;

  const _DraftSection({
    required this.drafts,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Draft (${drafts.length})',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: drafts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final draft = drafts[index];
              return _DraftCard(
                draft: draft,
                onTap: () => onTap(draft),
                onDelete: () => onDelete(draft),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DraftCard extends StatelessWidget {
  final FeedDraft draft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DraftCard({
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  String? get _thumbPath {
    if (draft.thumbnailPath != null && draft.thumbnailPath!.isNotEmpty) {
      return draft.thumbnailPath;
    }
    if (draft.mediaPaths.isNotEmpty) return draft.mediaPaths.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = draft.type == 'video';
    final thumb = _thumbPath;
    return SizedBox(
      width: 78,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: thumb != null
                          ? Image.file(
                              File(thumb),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _DraftThumbFallback(),
                            )
                          : const _DraftThumbFallback(),
                    ),
                    if (draft.broken)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: const Center(
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 5,
                      top: 5,
                      child: _DraftTypeBadge(
                        icon: isVideo
                            ? Icons.videocam_rounded
                            : Icons.photo_rounded,
                        label: !isVideo && draft.mediaPaths.length > 1
                            ? '${draft.mediaPaths.length} foto'
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                formatRelativeTime(
                  DateTime.fromMillisecondsSinceEpoch(draft.savedAtMs),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill badge tipe media di pojok kartu draft — tint lembut, bukan fill
/// saturated (match memory `design-subtle-badges`).
class _DraftTypeBadge extends StatelessWidget {
  final IconData icon;
  final String? label;

  const _DraftTypeBadge({required this.icon, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 11),
          if (label != null) ...[
            const SizedBox(width: 3),
            Text(
              label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DraftThumbFallback extends StatelessWidget {
  const _DraftThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF161A24),
      child: Center(
        child: Icon(Icons.image_outlined, color: Colors.white38, size: 22),
      ),
    );
  }
}

class _FeedGalleryTabs extends StatelessWidget {
  final List<_PostsFilter> filters;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _FeedGalleryTabs({
    required this.filters,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 24),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final active = index == activeIndex;
          return InkWell(
            onTap: () => onTap(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    filter.label,
                    style: TextStyle(
                      color: active ? _brandBlue : cs.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    width: active ? 38 : 0,
                    decoration: BoxDecoration(
                      color: _brandBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryPostTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;

  const _GalleryPostTile({
    required this.post,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onTapDown: (_) => onTapDown?.call(),
        onTapCancel: onTapCancel,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PostThumbnail(post: post),
              if (post.isVideo)
                const Positioned(
                  right: 7,
                  top: 7,
                  child: _PostMediaTypeIcon(icon: Icons.play_arrow_rounded),
                )
              else if (post.isCarousel || post.mediaItems.length > 1)
                const Positioned(
                  right: 7,
                  top: 7,
                  child: _PostMediaTypeIcon(icon: Icons.collections_rounded),
                ),
              Positioned(
                left: 7,
                bottom: 7,
                child: _StatusBadge(status: post.statusInfo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  final FeedPost post;
  const _PostThumbnail({required this.post});

  @override
  Widget build(BuildContext context) {
    final imageUrl = _thumbnailUrlForPost(post);
    if (imageUrl == null) return const _PostThumbnailFallback();

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => const _PostThumbnailFallback(),
      errorWidget: (_, __, ___) => const _PostThumbnailFallback(),
    );
  }
}

String? _thumbnailUrlForPost(FeedPost post) {
  final thumbnail = post.thumbnailUrl;
  if (thumbnail != null && thumbnail.trim().isNotEmpty) return thumbnail.trim();
  for (final item in post.mediaItems) {
    final itemThumb = item.thumbnailUrl;
    if (itemThumb != null && itemThumb.trim().isNotEmpty) {
      return itemThumb.trim();
    }
    if (item.mediaUrl.trim().isNotEmpty) return item.mediaUrl.trim();
  }
  final preview = post.previewMediaUrl;
  return preview.trim().isNotEmpty ? preview.trim() : null;
}

class _PostThumbnailFallback extends StatelessWidget {
  const _PostThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.photo_library_rounded,
          color: cs.onSurfaceVariant,
          size: 28,
        ),
      ),
    );
  }
}

class _PostMediaTypeIcon extends StatelessWidget {
  final IconData icon;
  const _PostMediaTypeIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 17,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final FeedPostStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = switch (status) {
      FeedPostStatus.pending => const _StatusStyle(
          label: 'Menunggu',
          bg: Color(0xFFFFF4D6),
          fg: Color(0xFFB45309),
          icon: Icons.schedule_rounded,
        ),
      FeedPostStatus.rejected => const _StatusStyle(
          label: 'Ditolak',
          bg: Color(0xFFEF4444),
          fg: Colors.white,
          icon: Icons.cancel_rounded,
        ),
      FeedPostStatus.active || FeedPostStatus.unknown => null,
    };

    if (style == null) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: style.bg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.fg, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.fg,
                fontSize: style.label.length > 9 ? 9.2 : 10.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _StatusStyle({
    required this.label,
    required this.bg,
    required this.fg,
    required this.icon,
  });
}

class _EmptyPostsCard extends StatelessWidget {
  final VoidCallback onUpload;
  const _EmptyPostsCard({required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 18),
        Icon(
          Icons.photo_library_outlined,
          color: cs.onSurfaceVariant,
          size: 44,
        ),
        const SizedBox(height: 14),
        Text(
          'Belum ada postingan',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Bagikan foto atau video hewan kesayanganmu ke Feed Natalo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: onUpload,
            style: FilledButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text(
              'Buat Postingan',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  final String label;
  const _FilteredEmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Belum ada postingan untuk $label.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MemberPostPreviewScreen extends StatefulWidget {
  final FeedPost post;

  const _MemberPostPreviewScreen({required this.post});

  @override
  State<_MemberPostPreviewScreen> createState() =>
      _MemberPostPreviewScreenState();
}

class _MemberPostPreviewScreenState extends State<_MemberPostPreviewScreen> {
  int _index = 0;

  List<FeedMedia> get _items {
    if (widget.post.mediaItems.isNotEmpty) return widget.post.mediaItems;
    final mediaUrl = widget.post.previewMediaUrl;
    if (mediaUrl.trim().isEmpty) return const [];
    return [
      FeedMedia(
        id: '${widget.post.id}-preview',
        mediaUrl: mediaUrl,
        thumbnailUrl: widget.post.thumbnailUrl,
        mediaType: widget.post.isVideo ? 'video' : 'image',
        durationSeconds: widget.post.durationSec,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final isVideo = widget.post.isVideo;
    final isSlider = !isVideo && items.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: isVideo
                  ? _PreviewVideoPlayer(
                      mediaUrl: widget.post.previewMediaUrl,
                      thumbnailUrl: widget.post.thumbnailUrl,
                    )
                  : isSlider
                      ? PageView.builder(
                          itemCount: items.length,
                          onPageChanged: (index) =>
                              setState(() => _index = index),
                          itemBuilder: (context, index) {
                            return _PreviewImage(
                              imageUrl: items[index].mediaUrl,
                            );
                          },
                        )
                      : _PreviewImage(
                          imageUrl: items.isEmpty
                              ? widget.post.previewMediaUrl
                              : items.first.mediaUrl,
                        ),
            ),
            Positioned(
              left: 8,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            if (isSlider)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1}/${items.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            if (isSlider)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(items.length, (index) {
                    final active = index == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: active ? 0.92 : 0.42,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  final String imageUrl;

  const _PreviewImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const _PreviewPlaceholder(icon: Icons.image_outlined);
    }

    return Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const _PreviewPlaceholder(icon: Icons.image_outlined),
          errorWidget: (_, __, ___) =>
              const _PreviewPlaceholder(icon: Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _PreviewVideoPlayer extends StatefulWidget {
  final String mediaUrl;
  final String? thumbnailUrl;

  const _PreviewVideoPlayer({
    required this.mediaUrl,
    required this.thumbnailUrl,
  });

  @override
  State<_PreviewVideoPlayer> createState() => _PreviewVideoPlayerState();
}

class _PreviewVideoPlayerState extends State<_PreviewVideoPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    appSettingsStore.addListener(_onSettingsChanged);
    _initVideo();
  }

  void _onSettingsChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(
      controller.setVolume(appSettingsStore.feedMuted ? 0 : 1),
    );
  }

  Future<void> _initVideo() async {
    if (widget.mediaUrl.trim().isEmpty) {
      setState(() => _error = 'Video tidak tersedia');
      return;
    }

    setState(() => _loading = true);
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl),
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      await controller.setLooping(true);
      await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
      setState(() => _loading = false);
    } catch (_) {
      await controller.dispose();
      if (!mounted || _controller != controller) return;
      setState(() {
        _controller = null;
        _loading = false;
        _error = 'Video belum bisa diputar';
      });
    }
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
    setState(() {});
  }

  @override
  void dispose() {
    appSettingsStore.removeListener(_onSettingsChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final playing = ready && controller.value.isPlaying;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 9 / 16,
                child: VideoPlayer(controller),
              ),
            )
          else if (widget.thumbnailUrl != null &&
              widget.thumbnailUrl!.trim().isNotEmpty)
            _PreviewImage(imageUrl: widget.thumbnailUrl!)
          else
            const _PreviewPlaceholder(icon: Icons.play_circle_outline_rounded),
          if (_loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          if (!playing && _error == null)
            Center(
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: _brandBlue,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final IconData icon;

  const _PreviewPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(
          icon,
          color: Colors.white24,
          size: 72,
        ),
      ),
    );
  }
}
