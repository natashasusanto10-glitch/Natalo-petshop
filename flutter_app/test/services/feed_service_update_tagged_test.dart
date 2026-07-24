import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/new_post_user_tag.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

void main() {
  test('taggedUsersToJson: foto bawa mediaIndex/x/y, video polos', () {
    final json = FeedService.taggedUsersToJson(const [
      NewPostUserTag(
          userId: 'u1',
          username: 'a',
          mediaIndex: 0,
          x: 0.5,
          y: 0.25),
      NewPostUserTag(userId: 'u2', username: 'b'),
    ]);
    expect(json, [
      {'userId': 'u1', 'mediaIndex': 0, 'x': 0.5, 'y': 0.25},
      {'userId': 'u2'},
    ]);
  });
}
