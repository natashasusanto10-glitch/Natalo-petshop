import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';

void main() {
  test('parse commentId (camelCase)', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'eventType': 'feed_new_comment', 'feedPostId': 'p1',
      'commentId': 'c123',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.commentId, 'c123');
  });

  test('parse comment_id (snake_case fallback)', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'comment_id': 'c456',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.commentId, 'c456');
  });

  test('commentId null saat absen', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.commentId, isNull);
  });

  test('copyWith(read:) mempertahankan commentId', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'commentId': 'c789',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.copyWith(read: true).commentId, 'c789');
  });
}
