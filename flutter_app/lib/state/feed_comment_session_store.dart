import 'dart:collection';

import '../models/feed_comment.dart';

/// Transient UI state for one viewer reading one post's comments.
///
/// This deliberately stays in memory. Comment drafts and reading position are
/// useful while navigating Feed/Profile, but should not survive logout or an
/// app restart without an explicit draft feature.
class FeedCommentSession {
  String draftText = '';
  FeedComment? replyTarget;
  List<FeedComment> comments = const [];
  String? nextCursor;
  bool hasLoaded = false;
  Map<String, int> visibleReplyCounts = const {};
  double scrollOffset = 0;
  double? sheetExtent;

  void replaceComments(List<FeedComment> value, String? cursor) {
    comments = List<FeedComment>.unmodifiable(value);
    nextCursor = cursor;
    hasLoaded = true;
  }

  void replaceVisibleReplyCounts(Map<String, int> value) {
    visibleReplyCounts = Map<String, int>.unmodifiable(value);
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
      _sessions.remove(_sessions.keys.first);
    }
    return session;
  }

  bool contains({required String viewerId, required String postId}) {
    return _sessions.containsKey(_key(viewerId, postId));
  }

  void clearForViewer(String viewerId) {
    final prefix = '$viewerId\u0000';
    _sessions.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clear() => _sessions.clear();

  String _key(String viewerId, String postId) => '$viewerId\u0000$postId';
}

final FeedCommentSessionStore feedCommentSessionStore =
    FeedCommentSessionStore();
