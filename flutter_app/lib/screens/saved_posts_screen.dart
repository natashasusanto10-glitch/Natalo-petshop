import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../state/feed_store.dart';
import '../theme/natalo_colors.dart';
import 'member_post_detail_screen.dart';

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
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
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
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_handleScroll);
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  List<FeedPost> get _allSavedPosts => feedStore
      .getMany(_postIds)
      .where((post) => post.viewerSaved)
      .toList(growable: false);

  List<FeedPost> get _visiblePosts {
    final posts = _allSavedPosts;
    if (_tabController.index == 0) return posts;
    return posts
        .where((post) => post.hasLinkedProducts)
        .toList(growable: false);
  }

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
      _scheduleShoppingPrefetch();
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
          ...posts
              .where((post) => knownIds.add(post.id))
              .map((post) => post.id),
        ];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
      _scheduleShoppingPrefetch();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _scheduleShoppingPrefetch() {
    if (_tabController.index != 1 ||
        _visiblePosts.length >= 6 ||
        _loadingMore ||
        _nextCursor == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabController.index != 1) return;
      unawaited(_loadMore());
    });
  }

  Future<void> _openPost(List<FeedPost> posts, int index) async {
    final post = posts[index];
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MemberPostDetailScreen(
          post: post,
          posts: [post],
          authorName: post.author.displayName,
          authorPhotoUrl: post.author.avatarUrl,
          authorInitial: post.author.initial,
          isOwner: false,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: colors.surface,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: const Text(
          'Postingan Tersimpan',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) {
            setState(() {});
            _scheduleShoppingPrefetch();
          },
          labelColor: NataloColors.primary,
          unselectedLabelColor: colors.onSurfaceVariant,
          indicatorColor: NataloColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Semua'),
            Tab(text: 'Belanja'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: feedStore,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final posts = _visiblePosts;
    if (_loading && _postIds.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: NataloColors.primary,
          strokeWidth: 2.4,
        ),
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
      final shopping = _tabController.index == 1;
      return _SavedPostsMessage(
        icon: shopping
            ? Icons.shopping_bag_outlined
            : Icons.bookmark_border_rounded,
        title: shopping
            ? 'Belum ada postingan belanja tersimpan'
            : 'Belum ada postingan tersimpan',
        subtitle: shopping
            ? 'Postingan tersimpan yang menampilkan produk akan muncul di sini.'
            : 'Tap ikon simpan di Feed untuk melihatnya lagi di sini.',
        onRefresh: _loadInitial,
      );
    }

    return RefreshIndicator(
      color: NataloColors.primary,
      onRefresh: _loadInitial,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _SavedPostTile(
                  post: posts[index],
                  onTap: () => _openPost(posts, index),
                ),
                childCount: posts.length,
              ),
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
                            color: NataloColors.primary,
                            strokeWidth: 2.2,
                          ),
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

class _SavedPostTile extends StatelessWidget {
  final FeedPost post;
  final VoidCallback onTap;

  const _SavedPostTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final previewUrl = post.previewMediaUrl.trim();
    return Semantics(
      button: true,
      label: 'Buka postingan tersimpan dari ${post.author.displayName}',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          key: ValueKey('saved-post-${post.id}'),
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: previewUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const _SavedPostFallback(),
                  errorWidget: (_, __, ___) => const _SavedPostFallback(),
                )
              else
                const _SavedPostFallback(),
              if (post.isVideo || post.isCarousel)
                Positioned(
                  top: 7,
                  right: 7,
                  child: _MediaBadge(
                    icon: post.isVideo
                        ? Icons.play_arrow_rounded
                        : Icons.collections_rounded,
                  ),
                ),
              if (post.hasLinkedProducts)
                const Positioned(
                  left: 7,
                  bottom: 7,
                  child: _MediaBadge(icon: Icons.shopping_bag_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedPostFallback extends StatelessWidget {
  const _SavedPostFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MediaBadge extends StatelessWidget {
  final IconData icon;

  const _MediaBadge({required this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, color: Colors.white, size: 17),
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
    return RefreshIndicator(
      color: NataloColors.primary,
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
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 13,
                height: 1.45,
              ),
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
