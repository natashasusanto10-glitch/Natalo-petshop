# Task 7: Universal Links/App Links and deep-link lifecycle

## Scope delivered

- Added a pure parser for production HTTPS Feed, product, and profile links.
- Query parameters, including preview cache token `v`, are ignored for route
  identity and deduplication.
- Added a single pending public target, bounded two-second deduplication, and
  a first-mounted-frame lifecycle flush for cold starts.
- Preserved the existing Feed smart-opening path: video opens fullscreen,
  while image/carousel opens Postingan; product still resolves by slug and
  public profile remains lowercase.
- Rejected deceptive hosts, non-HTTPS links, malformed public paths, and
  unrelated schemes without navigating to a fallback screen.
- Added `/feed/*` to the iOS AASA route.

## Platform audit

- Android manifest already has `android:autoVerify="true"` and HTTPS handlers
  for both `natalopetshop.com` and `www.natalopetshop.com`; unchanged.
- iOS Runner.entitlements already has Associated Domains for both hosts;
  unchanged.
- Android Asset Links retains package `com.natalo.petshop` and the production
  Play signing fingerprint; unchanged.
- AASA now includes `/feed/*` in addition to product and public-profile paths.

## Verification

- RED: parser/lifecycle tests failed before implementation because the parser,
  target types, and injected dispatcher did not exist.
- GREEN: `flutter test test/services/deep_link_router_test.dart
  test/services/deep_link_service_test.dart
  test/services/deep_link_service_navigator_race_test.dart` passed: 9 tests.
- `flutter analyze lib/services/deep_link_router.dart
  lib/services/deep_link_service.dart lib/main.dart` passed.
- `npx tsx --test tests/deep-link-association.test.ts` passed: 3 tests.
- `npx eslint tests/deep-link-association.test.ts
  app/.well-known/apple-app-site-association/route.ts` passed.
- `git diff --check` passed.
- Repository-wide `npx tsc --noEmit` remains blocked by six pre-existing
  unrelated test files importing unavailable `vitest`; the targeted AASA and
  Asset Links test executes successfully.

## Commit

- `b1bb82ca fix(deep-link): queue and deduplicate public share links`

## Device gates still required

- Deploy the AASA route before mobile builds, then verify apex and `www` serve
  it as JSON without redirect.
- Android device: test Feed video, image/carousel, product, and profile URLs
  from terminated, background, and foreground states; one tap must create one
  route and back stack must be correct.
- iOS physical device/TestFlight: repeat the same lifecycle matrix. Simulator
  smoke is useful, but Universal Link verification requires device/TestFlight.
- Confirm an uninstalled app opens the corresponding public web page.
