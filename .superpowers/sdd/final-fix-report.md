# Final fix report: official public identity

## Change

Centralized the public official account label as `Natalo Petshop Official` in
`flutter_app/lib/constants/official_brand.dart`. Feed authors, mention picker,
inline mentions, product-feed fallback authors, public profiles, and likers now
use this constant. Existing `isOfficial`/`isAdminOfficial` checks and
`OfficialVerifiedBadge` rendering were preserved.

## Verification

- `dart format` on all changed Dart files
- `flutter test test/models/feed_comment_test.dart test/models/official_brand_test.dart`
- Result: 16 tests passed

General store/app marketing copy such as app title and chat welcome was not
renamed because it is not an official account identity surface.
