import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';

void main() {
  test('public profile tile keys stay stable and scoped to their content tab',
      () {
    final keys = ProfilePostOriginKeyCache();

    final allTile = keys.forPost(PublicProfileContentFilter.all, 'video-1');

    expect(
      keys.forPost(PublicProfileContentFilter.all, 'video-1'),
      same(allTile),
    );
    expect(
      keys.forPost(PublicProfileContentFilter.video, 'video-1'),
      isNot(same(allTile)),
    );
  });
}
