import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/feed_comment.dart';

/// Transient UI state for one viewer reading one post's comments.
///
/// This deliberately stays in memory. Comment drafts and reading position are
/// useful while navigating Feed/Profile, but should not survive logout or an
/// app restart without an explicit draft feature.
class FeedCommentSession extends ChangeNotifier {
  String draftText = '';
  FeedComment? replyTarget;
  List<FeedComment> comments = const [];
  String? nextCursor;
  bool hasLoaded = false;
  Map<String, int> visibleReplyCounts = const {};
  double scrollOffset = 0;
  double? sheetExtent;
  DateTime? syncCursor;

  int _revision = 0;
  Object? _lastWriter;

  /// Monotonic revision for comment content only. Draft, reply target, scroll,
  /// and sheet extent deliberately stay local UI state and do not rebuild a
  /// second mounted drawer.
  int get revision => _revision;

  /// Lets a mounted sheet ignore the synchronous notification produced by
  /// its own write while still adopting writes from another surface.
  Object? get lastWriter => _lastWriter;

  /// LRU eviction must never discard the canonical object while a drawer is
  /// listening to it.
  bool get isObserved => hasListeners;

  void replaceComments(
    List<FeedComment> value,
    String? cursor, {
    Object? source,
    DateTime? syncedAt,
    Iterable<String> removedIds = const <String>[],
  }) {
    final removed = removedIds.toSet();
    comments = List<FeedComment>.unmodifiable(
      removed.isEmpty ? value : _withoutRemovedComments(value, removed),
    );
    nextCursor = cursor;
    hasLoaded = true;
    if (syncedAt != null) syncCursor = syncedAt;
    _lastWriter = source;
    _revision++;
    notifyListeners();
  }

  void replaceVisibleReplyCounts(Map<String, int> value) {
    visibleReplyCounts = Map<String, int>.unmodifiable(value);
  }

  void reset() {
    draftText = '';
    replyTarget = null;
    comments = const [];
    nextCursor = null;
    hasLoaded = false;
    visibleReplyCounts = const {};
    scrollOffset = 0;
    sheetExtent = null;
    syncCursor = null;
    _lastWriter = null;
    _revision++;
    notifyListeners();
  }
}

/// Small LRU cache shared by Postingan and fullscreen Feed comment drawers.
/// Sessions are scoped by viewer to prevent drafts leaking across accounts.
class FeedCommentSessionStore {
  FeedCommentSessionStore({this.maxSessions = 16}) : assert(maxSessions > 0);

  final int maxSessions;
  final LinkedHashMap<String, FeedCommentSession> _sessions =
      LinkedHashMap<String, FeedCommentSession>();

  int get length => _sessions.length;

  FeedCommentSession sessionFor({
    required String viewerId,
    required String postId,
  }) {
    final key = _key(viewerId, postId);
    final existing = _sessions.remove(key);
    final session = existing ?? FeedCommentSession();
    _sessions[key] = session;
    while (_sessions.length > maxSessions) {
      String? evictionKey;
      for (final entry in _sessions.entries) {
        if (entry.key != key && !entry.value.isObserved) {
          evictionKey = entry.key;
          break;
        }
      }
      // All sessions are mounted. Temporary overflow is safer than replacing
      // a live canonical session with a second object for the same post.
      if (evictionKey == null) break;
      _sessions.remove(evictionKey);
    }
    return session;
  }

  bool contains({required String viewerId, required String postId}) {
    return _sessions.containsKey(_key(viewerId, postId));
  }

  void clearForViewer(String viewerId) {
    final prefix = '$viewerId\u0000';
    final matching = _sessions.entries
        .where((entry) => entry.key.startsWith(prefix))
        .toList(growable: false);
    for (final entry in matching) {
      entry.value.reset();
      _sessions.remove(entry.key);
    }
  }

  void clear() {
    for (final session in _sessions.values.toList(growable: false)) {
      session.reset();
    }
    _sessions.clear();
  }

  String _key(String viewerId, String postId) => '$viewerId\u0000$postId';
}

final FeedCommentSessionStore feedCommentSessionStore =
    FeedCommentSessionStore();

List<FeedComment> _withoutRemovedComments(
  List<FeedComment> comments,
  Set<String> removedIds,
) {
  return comments
      .where((comment) => !removedIds.contains(comment.id))
      .map((comment) {
    final replies = comment.replies
        .where((reply) => !removedIds.contains(reply.id))
        .toList(growable: false);
    if (replies.length == comment.replies.length) return comment;
    final removedReplyCount = comment.replies.length - replies.length;
    return comment.copyWith(
      replies: replies,
      replyCount: (comment.replyCount - removedReplyCount)
          .clamp(replies.length, 1 << 30),
    );
  }).toList(growable: false);
}
