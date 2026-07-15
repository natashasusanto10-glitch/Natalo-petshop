import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/constants/official_brand.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/widgets/mention_picker.dart';

void main() {
  test('official identity is centralized', () {
    expect(kOfficialBrandName, 'Natalo Petshop Official');
  });

  test('official feed authors and mention suggestions use the brand name', () {
    const author =
        FeedAuthor(id: 'admin', name: 'Private Staff', isAdmin: true);
    const mention = MentionUser(
      id: 'admin',
      name: 'Private Staff',
      username: 'natalopetshop',
      isOfficial: true,
    );
    expect(author.displayName, kOfficialBrandName);
    expect(mention.displayLabel, kOfficialBrandName);
  });
}
