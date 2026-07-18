import 'dart:async';

import 'package:flutter/material.dart';

import '../features/feed/widgets/gallery_post_tile.dart';
import '../features/feed/widgets/post_gallery_opener.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/feed_store.dart';
import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/profile_grid_geometry.dart';

typedef SavedPostsFetcher = Future<FeedPage> Function(
    {String? cursor, required int limit});

class SavedPostsScreen extends StatefulWidget {
  final SavedPostsFetcher fetchPosts;

  SavedPostsScreen({super.key, SavedPostsFetcher? fetchPosts})
      : fetchPosts = fetchPosts ?? feedService.fetchSavedPosts;

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen>
    with PostGalleryOpener<SavedPostsScreen> {
  final ScrollController _scrollController = ScrollController();

  List<String> _postIds = const [];
  String? _nextCursor;
  String? _errorText;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  int _loadGeneration = 0;

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

  List<FeedPost> get _savedPosts => feedStore
      .getMany(_postIds)
      .where((post) => post.viewerSaved)
      .toList(growable: false);

  List<FeedPost> _normalizeSaved(Iterable<FeedPost> posts) => posts
      .map((post) => post.viewerSaved ? post : post.copyWith(viewerSaved: true))
      .toList(growable: false);

  Future<void> _loadInitial() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _errorText = null;
        _loadMoreFailed = false;
      });
    }
    final fetchedAt = DateTime.now();
    try {
      final page = await widget.fetchPosts(limit: 20);
      if (!mounted || generation != _loadGeneration) return;
      final posts = _normalizeSaved(page.items);
      feedStore.mergeFromServer(posts, fetchedAt: fetchedAt);
      setState(() {
        _postIds = posts.map((post) => post.id).toList(growable: false);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _errorText = error is ApiException && error.statusCode == 401
            ? 'Masuk kembali untuk melihat postingan tersimpan.'
            : 'Postingan tersimpan belum bisa dimuat.';
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
    final fetchedAt = DateTime.now();
    try {
      final page = await widget.fetchPosts(cursor: cursor, limit: 20);
      if (!mounted || generation != _loadGeneration) return;
      final posts = _normalizeSaved(page.items);
      feedStore.mergeFromServer(posts, fetchedAt: fetchedAt);
      final knownIds = _postIds.toSet();
      setState(() {
        _postIds = [
          ..._postIds,
          ...posts.where((post) => knownIds.add(post.id)).map((p) => p.id),
        ];
        _nextCursor = page.nextCursor;
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

  Future<void> _openPost(List<FeedPost> posts, int index) async {
    await openPostGallery(
      posts: posts,
      index: index,
      loadMore: (cursor) => widget.fetchPosts(cursor: cursor, limit: 20),
      authorIsOfficial: false,
      isOwner: false,
      authorPerPost: true,
      initialNextCursor: _nextCursor,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          // Chevron "<" ala IG — samakan dgn back button halaman Postingan
          // (member_post_detail_screen).
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.onSurface, size: 24),
          tooltip: 'Kembali',
        ),
        title: Text(
          'Postingan Tersimpan',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: NataloWeight.strong,
          ),
        ),
        centerTitle: true,
        titleSpacing: 0,
      ),
      body: AnimatedBuilder(
        animation: feedStore,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final posts = _savedPosts;
    if (_loading && _postIds.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: NataloColors.primary, strokeWidth: 2.4),
      );
    }
    if (_errorText != null && _postIds.isEmpty) {
      return _SavedPostsMessage(
        icon: Icons.cloud_off_rounded,
        title: _errorText!,
        actionLabel: 'Coba lagi',
        onAction: _loadInitial,
      );
    }
    if (posts.isEmpty) {
      return _SavedPostsMessage(
        icon: Icons.bookmark_border_rounded,
        title: 'Belum ada postingan tersimpan',
        subtitle: 'Tap ikon simpan di Feed untuk melihatnya lagi di sini.',
        onRefresh: _loadInitial,
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
            itemCount: posts.length,
            itemBuilder: (context, index) => GalleryPostTile(
              key: tileKeyFor(posts[index].id),
              post: posts[index],
              onTap: () => _openPost(posts, index),
              onTapDown: () => preparePostVideo(posts[index]),
              onTapCancel: () => cancelPreparedPost(posts[index].id),
              showStatusBadge: false,
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

class _SavedPostsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final Future<void> Function()? onRefresh;

  const _SavedPostsMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NataloPawRefreshIndicator(
      onRefresh: onRefresh ?? onAction ?? () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 88, 32, 32),
        children: [
          Icon(icon, size: 54, color: colors.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 17,
              fontWeight: NataloWeight.strong,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.onSurfaceVariant, fontSize: 13, height: 1.45),
            ),
          ],
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
