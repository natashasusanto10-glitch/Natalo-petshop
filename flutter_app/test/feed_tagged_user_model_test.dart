import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
  Map<String, dynamic> basePostJson() => {
        'id': 'post1',
        'title': 'halo',
        'kind': 'PHOTO_CAROUSEL',
        'author': {'id': 'a1', 'name': 'Asiong', 'username': 'asiong'},
        'taggedUsers': [
          {
            'userId': 'u1',
            'username': 'budi',
            'name': 'Budi',
            'profilePhotoUrl': 'https://cdn/x/budi.jpg',
            'mediaId': 'm1',
            'mediaIndex': 0,
            'x': 0.25,
            'y': 0.75,
          },
          {
            'userId': 'u2',
            'username': 'cici',
            'name': 'Cici',
            'profilePhotoUrl': null,
            'mediaId': null,
            'mediaIndex': null,
            'x': null,
            'y': null,
          },
        ],
      };

  test('fromJson parse taggedUsers', () {
    final post = FeedPost.fromJson(basePostJson());
    expect(post.taggedUsers, hasLength(2));
    expect(post.taggedUsers.first.userId, 'u1');
    expect(post.taggedUsers.first.x, 0.25);
    expect(post.taggedUsers.last.mediaIndex, isNull);
  });

  test('toJson lossless round-trip taggedUsers', () {
    final post = FeedPost.fromJson(basePostJson());
    final roundTripped = FeedPost.fromJson(post.toJson());
    expect(roundTripped.taggedUsers, hasLength(2));
    final a = roundTripped.taggedUsers.first;
    expect(a.userId, 'u1');
    expect(a.username, 'budi');
    expect(a.name, 'Budi');
    expect(a.profilePhotoUrl, 'https://cdn/x/budi.jpg');
    expect(a.mediaId, 'm1');
    expect(a.mediaIndex, 0);
    expect(a.x, 0.25);
    expect(a.y, 0.75);
    final b = roundTripped.taggedUsers.last;
    expect(b.userId, 'u2');
    expect(b.x, isNull);
  });

  test('taggedUsers absen → list kosong', () {
    final json = basePostJson()..remove('taggedUsers');
    expect(FeedPost.fromJson(json).taggedUsers, isEmpty);
  });
}
