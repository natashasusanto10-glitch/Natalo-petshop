import 'dart:async';

import 'package:flutter/material.dart';

import '../features/feed/widgets/gallery_post_tile.dart';
import '../features/feed/widgets/post_gallery_opener.dart';
import '../models/feed_post.dart';
import '../services/feed_service.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_grid_geometry.dart';

typedef HashtagPostsFetcher = Future<HashtagPageResult> Function(
  String name, {
  String? cursor,
});

/// Halaman hashtag (Spec C, §3) — grid postingan ber-tag `#name` dari
/// BANYAK author berbeda (beda dengan grid profil yang selalu single-author).
/// Struktur loading/error/empty/paginasi mengikuti `SavedPostsScreen`
/// (grid + `GalleryPostTile` + mixin `PostGalleryOpener`), TAPI tanpa
/// filter interaksi (`viewerSaved`) — tampilkan persis apa yang backend
/// balikan untuk hashtag ini, cross-account.
class HashtagScreen extends StatefulWidget {
  final String name;
  final HashtagPostsFetcher fetcher;

  HashtagScreen({
    super.key,
    required this.name,
    HashtagPostsFetcher? fetcher,
  }) : fetcher = fetcher ?? feedService.fetchHashtagPosts;

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen>
    with PostGalleryOpener<HashtagScreen> {
  final ScrollController _scrollController = ScrollController();

  List<FeedPost> _posts = const [];
  int _postCount = 0;
  String? _nextCursor;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  int _loadGeneration = 0;

  /// Nama kanonik (lowercase) — dipakai untuk judul AppBar DAN setiap
  /// request ke fetcher, supaya request selalu konsisten walau caller
  /// (deep link dst.) mengirim casing campur.
  String get _canonicalName => widget.name.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        _nextCursor == null) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadInitial() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _loadMoreFailed = false;
      });
    }
    try {
      final result = await widget.fetcher(_canonicalName);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _posts = result.posts;
        _postCount = result.postCount;
        _nextCursor = result.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || cursor == null) return;
    final generation = _loadGeneration;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final result = await widget.fetcher(_canonicalName, cursor: cursor);
      if (!mounted || generation != _loadGeneration) return;
      final knownIds = _posts.map((post) => post.id).toSet();
      setState(() {
        _posts = [
          ..._posts,
          ...result.posts.where((post) => knownIds.add(post.id)),
        ];
        // Selalu ambil count TERBARU dari response (akurat), bukan nilai
        // yang di-cache dari page pertama.
        _postCount = result.postCount;
        _nextCursor = result.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  static const _heroScope = 'hashtag';

  /// Paginasi TERPISAH dipakai viewer fullscreen (`MemberPostDetailScreen`)
  /// saat scroll melewati batas awal — bukan grid ini. Adaptasi
  /// `HashtagPageResult` (bentuk hashtag) → `FeedPage` (kontrak
  /// `ScopedPostPageLoader` bersama semua viewer post).
  Future<FeedPage> _loadMoreForViewer(String? cursor) async {
    final result = await widget.fetcher(_canonicalName, cursor: cursor);
    return FeedPage(items: result.posts, nextCursor: result.nextCursor);
  }

  Future<void> _openPost(int index) async {
    await openPostGallery(
      posts: _posts,
      index: index,
      loadMore: _loadMoreForViewer,
      authorIsOfficial: false,
      isOwner: false,
      // Multi-author: setiap post di viewer HARUS pakai identitas
      // author-nya sendiri (post.author.*), bukan satu identitas viewer
      // yang dibagi rata ke semua post (lihat _postWithResolvedAuthor +
      // _PostFeedItem di member_post_detail_screen.dart).
      authorPerPost: true,
      initialNextCursor: _nextCursor,
      heroScope: _heroScope,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _canonicalName;
    final subtitle =
        (!_loading && _error == null) ? '$_postCount postingan' : null;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.onSurface, size: 24),
          tooltip: 'Kembali',
        ),
        title: Semantics(
          header: true,
          excludeSemantics: true,
          label:
              subtitle == null ? 'Hashtag #$name' : 'Hashtag #$name, $subtitle',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '#$name',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: NataloWeight.strong,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: NataloWeight.body,
                  ),
                ),
              ],
            ],
          ),
        ),
        centerTitle: true,
        titleSpacing: 0,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: NataloColors.primary, strokeWidth: 2.4),
      );
    }
    if (_error != null && _posts.isEmpty) {
      // Error != empty: WAJIB AppErrorState + retry — insiden lama
      // "error-nyamar-kosong" (lihat app_ui.dart) terjadi karena screen lain
      // menelan error jadi tampilan kosong biasa. `description` di-override
      // supaya tidak mengulang kata "coba lagi" dari retry button (retry
      // button sendiri sudah punya label itu).
      return NataloPawRefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 60),
          children: [
            AppErrorState(
              variant: appErrorVariantFromError(_error),
              title: 'Postingan belum bisa dimuat',
              description:
                  'Periksa koneksi internetmu, lalu tekan tombol di bawah ini.',
              onRetry: _loadInitial,
            ),
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return NataloPawRefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            AppEmptyState(
              icon: Icons.tag_rounded,
              title: 'Belum ada postingan dengan tag ini.',
            ),
          ],
        ),
      );
    }

    return NataloPawRefreshIndicator(
      onRefresh: _loadInitial,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverGrid.builder(
            gridDelegate: profileGridDelegate(),
            itemCount: _posts.length,
            itemBuilder: (context, index) => GalleryPostTile(
              key: tileKeyFor(_posts[index].id),
              post: _posts[index],
              onTap: () => _openPost(index),
              onTapDown: () => preparePostVideo(_posts[index]),
              onTapCancel: () => cancelPreparedPost(_posts[index].id),
              // Cross-account grid — jangan bocorkan status moderasi
              // (Menunggu/Ditolak) post orang lain ke viewer yang bukan
              // pemiliknya (sama seperti Postingan Tersimpan).
              showStatusBadge: false,
              heroScope: _heroScope,
            ),
          ),
          SliverToBoxAdapter(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: _loadingMore
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                              color: NataloColors.primary, strokeWidth: 2.2),
                        ),
                      )
                    : _loadMoreFailed
                        ? Center(
                            child: TextButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Muat lagi'),
                            ),
                          )
                        : const SizedBox(height: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
