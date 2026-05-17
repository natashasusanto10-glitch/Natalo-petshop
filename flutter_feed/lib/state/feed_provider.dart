import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/feed_api.dart';
import '../models/feed_post.dart';
import '../models/feed_comment.dart';
import '../services/network_tier.dart';

// Riverpod providers — single source of truth for feed list + per-post
// state (like, comments). Mirrors the optimistic-update pattern from
// components/feed/FeedClient.tsx and FeedVideoCard.tsx.

final feedApiProvider = Provider<FeedApi>((ref) => FeedApi.create());

final networkTierServiceProvider = Provider<NetworkTierService>((ref) {
  final svc = NetworkTierService();
  // Fire-and-forget init; widgets reading `current` get default until first event.
  svc.init();
  ref.onDispose(svc.dispose);
  return svc;
});

final networkInfoProvider = StreamProvider<NetworkInfo>((ref) {
  final svc = ref.watch(networkTierServiceProvider);
  return svc.stream;
});

// ─────────────────────────────────────────────────────────────────────────────
// Feed list — async notifier with cursor pagination

class FeedListState {
  final List<FeedPost> posts;
  final String? nextCursor;
  final bool loadingMore;
  final Object? error;

  const FeedListState({
    this.posts = const [],
    this.nextCursor,
    this.loadingMore = false,
    this.error,
  });

  FeedListState copyWith({
    List<FeedPost>? posts,
    String? nextCursor,
    bool? loadingMore,
    Object? error,
    bool clearCursor = false,
    bool clearError = false,
  }) =>
      FeedListState(
        posts: posts ?? this.posts,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );

  bool get hasMore => nextCursor != null;
}

class FeedListNotifier extends AsyncNotifier<FeedListState> {
  @override
  Future<FeedListState> build() async {
    final api = ref.read(feedApiProvider);
    final page = await api.listPosts();
    return FeedListState(posts: page.posts, nextCursor: page.nextCursor);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(feedApiProvider);
      final page = await api.listPosts();
      return FeedListState(posts: page.posts, nextCursor: page.nextCursor);
    });
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final api = ref.read(feedApiProvider);
      final page = await api.listPosts(cursor: current.nextCursor);
      state = AsyncValue.data(current.copyWith(
        posts: [...current.posts, ...page.posts],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      ));
    } catch (e) {
      state = AsyncValue.data(current.copyWith(loadingMore: false, error: e));
    }
  }

  /// Optimistic like toggle — UI state flips immediately, API call follows.
  /// Reverts on error (best-effort).
  Future<void> toggleLike(String postId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;

    final post = current.posts[idx];
    final optimistic = post.copyWith(
      viewerLiked: !post.viewerLiked,
      likeCount: post.likeCount + (post.viewerLiked ? -1 : 1),
    );
    final updatedList = [...current.posts]..[idx] = optimistic;
    state = AsyncValue.data(current.copyWith(posts: updatedList));

    try {
      final api = ref.read(feedApiProvider);
      final res = await api.toggleLike(postId);
      // Reconcile with server truth.
      final reconciled = optimistic.copyWith(
        viewerLiked: res.liked,
        likeCount: res.likeCount,
      );
      final refreshed = [...current.posts]..[idx] = reconciled;
      state = AsyncValue.data(current.copyWith(posts: refreshed));
    } catch (_) {
      // Revert.
      final reverted = [...current.posts]..[idx] = post;
      state = AsyncValue.data(current.copyWith(posts: reverted));
      rethrow;
    }
  }

  /// Bump local share count after native share dialog completes.
  Future<void> registerShare(String postId) async {
    final api = ref.read(feedApiProvider);
    final newCount = await api.registerShare(postId);
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final updated = [...current.posts]
      ..[idx] = current.posts[idx].copyWith(shareCount: newCount);
    state = AsyncValue.data(current.copyWith(posts: updated));
  }
}

final feedListProvider =
    AsyncNotifierProvider<FeedListNotifier, FeedListState>(
        FeedListNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Active video index — drives which card auto-plays. Updated by feed_screen
// PageView controller listener.

final activeVideoIndexProvider = StateProvider<int>((ref) => 0);

// ─────────────────────────────────────────────────────────────────────────────
// Comments per post — keyed by postId.

class CommentsNotifier
    extends FamilyAsyncNotifier<List<FeedComment>, String> {
  @override
  Future<List<FeedComment>> build(String postId) async {
    final api = ref.read(feedApiProvider);
    return api.listComments(postId);
  }

  Future<void> add(String content, {String? parentCommentId}) async {
    final api = ref.read(feedApiProvider);
    final newComment = await api.postComment(arg, content,
        parentCommentId: parentCommentId);
    final current = state.valueOrNull ?? const [];
    if (parentCommentId == null) {
      state = AsyncValue.data([newComment, ...current]);
    } else {
      // Insert as reply under parent.
      state = AsyncValue.data([
        for (final c in current)
          c.id == parentCommentId
              ? c.copyWith(replies: [...c.replies, newComment])
              : c,
      ]);
    }
  }

  Future<void> toggleLike(String commentId) async {
    final api = ref.read(feedApiProvider);
    final current = state.valueOrNull ?? const [];

    // Find comment (top-level or in replies).
    state = AsyncValue.data(_mapComments(current, (c) {
      if (c.id != commentId) return c;
      return c.copyWith(
        viewerLiked: !c.viewerLiked,
        likeCount: c.likeCount + (c.viewerLiked ? -1 : 1),
      );
    }));

    try {
      final res = await api.toggleCommentLike(commentId);
      final after = state.valueOrNull ?? const [];
      state = AsyncValue.data(_mapComments(after, (c) {
        if (c.id != commentId) return c;
        return c.copyWith(viewerLiked: res.liked, likeCount: res.likeCount);
      }));
    } catch (_) {
      // Revert on error.
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

List<FeedComment> _mapComments(
  List<FeedComment> input,
  FeedComment Function(FeedComment) fn,
) {
  return input.map((c) {
    final mapped = fn(c);
    if (mapped.replies.isEmpty) return mapped;
    return mapped.copyWith(replies: _mapComments(mapped.replies, fn));
  }).toList();
}

final commentsProvider = AsyncNotifierProviderFamily<CommentsNotifier,
    List<FeedComment>, String>(CommentsNotifier.new);
