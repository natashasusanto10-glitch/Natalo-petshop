import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/new_post_user_tag.dart';

void main() {
  test('toApiJson hanya kirim field kontrak API', () {
    const tag = NewPostUserTag(
      userId: 'u1',
      username: 'budi',
      name: 'Budi',
      profilePhotoUrl: 'https://cdn/b.jpg',
      mediaIndex: 2,
      x: 0.4,
      y: 0.6,
    );
    expect(tag.toApiJson(), {
      'userId': 'u1',
      'mediaIndex': 2,
      'x': 0.4,
      'y': 0.6,
    });
  });

  test('fromJson/toJson round-trip untuk draft persist', () {
    const tag = NewPostUserTag(
      userId: 'u1',
      username: 'budi',
      name: 'Budi',
      mediaIndex: 0,
      x: 0.1,
      y: 0.9,
    );
    final back = NewPostUserTag.fromJson(tag.toJson());
    expect(back.userId, 'u1');
    expect(back.username, 'budi');
    expect(back.mediaIndex, 0);
    expect(back.x, 0.1);
    expect(back.y, 0.9);
  });
}
