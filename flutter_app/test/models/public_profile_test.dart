import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';

void main() {
  test('parses mutual follower summary defensively', () {
    final summary = PublicProfileMutualSummary.fromJson({
      'items': [
        {
          'id': 'user-1',
          'name': 'Mona',
          'username': 'mona',
          'profilePhotoUrl': 'https://cdn.example/mona.jpg',
          'isOfficial': false,
        },
      ],
      'totalCount': 7,
    });
    expect(summary.items.single.id, 'user-1');
    expect(summary.items.single.username, 'mona');
    expect(summary.totalCount, 7);
  });

  test('missing and malformed mutual data falls back to empty', () {
    expect(
      PublicProfileMutualSummary.fromJson(null),
      PublicProfileMutualSummary.empty,
    );
    expect(
      PublicProfileMutualSummary.fromJson({'items': 'bad'}),
      PublicProfileMutualSummary.empty,
    );
  });

  test('summary count cannot be smaller than parsed items', () {
    final summary = PublicProfileMutualSummary.fromJson({
      'items': [
        {'id': 'user-1', 'name': 'Mona'},
        {'id': 'user-2', 'name': 'Riko'},
      ],
      'totalCount': 1,
    });
    expect(summary.totalCount, 2);
  });
}
