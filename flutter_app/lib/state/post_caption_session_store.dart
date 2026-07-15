import 'package:flutter/foundation.dart';

/// Tracks which post captions have been expanded during the current session.
class PostCaptionSessionStore extends ChangeNotifier {
  final Set<String> _expandedPostIds = <String>{};

  bool isExpanded(String postId) => _expandedPostIds.contains(postId);

  void markExpanded(String postId) {
    if (postId.isEmpty || !_expandedPostIds.add(postId)) {
      return;
    }
    notifyListeners();
  }
}

final PostCaptionSessionStore postCaptionSessionStore =
    PostCaptionSessionStore();
