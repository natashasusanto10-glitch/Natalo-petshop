import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

void main() {
  test('desired like state maps to idempotent HTTP verbs', () {
    expect(feedDesiredStateVerb(true), FeedDesiredStateVerb.put);
    expect(feedDesiredStateVerb(false), FeedDesiredStateVerb.delete);
  });

  test('comment query sends pagination and synchronization watermarks', () {
    final query = buildFeedCommentsQuery(
      cursor: 'page-2',
      limit: 20,
      syncCursor: DateTime.parse('2026-07-15T19:00:00+07:00'),
      syncTime: DateTime.parse('2026-07-15T19:01:00+07:00'),
    );

    expect(query, {
      'cursor': 'page-2',
      'limit': 20,
      'syncCursor': '2026-07-15T12:00:00.000Z',
      'syncTime': '2026-07-15T12:01:00.000Z',
    });
  });

  test('comment query remains compatible when sync metadata is absent', () {
    expect(buildFeedCommentsQuery(), {'limit': 30});
  });
}
