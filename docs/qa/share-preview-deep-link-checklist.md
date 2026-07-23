# Share Preview and Deep Link Release Checklist

Date: 2026-07-23

This checklist covers public Feed, product, and profile links shared from the
Natalo Flutter app. It records the automated verification completed locally
and the production/device checks that must occur before release.

## Automated verification completed

| Gate | Result |
| --- | --- |
| Share, deep-link, metadata, and OG-security server tests | Pass: 36 tests |
| Root server regression suite (`npm test`) | Pass |
| ESLint (`npm run lint`) | Pass |
| Focused Flutter share/deep-link/model tests | Pass: 33 tests |
| Focused Flutter analysis of all changed application files | Pass: no issues |
| Android debug APK | Pass: `build/app/outputs/flutter-apk/app-debug.apk` |
| Diff whitespace check | Pass |
| Share security static audit | Pass: no `og:video`, share media attachment, app-local URL, caption leakage, arbitrary OG proxy, or source-diff secret pattern |

The root TypeScript typecheck and full Flutter gates have known unrelated
baseline blockers. See [Task 8 report](../../.superpowers/sdd/task-8-report.md)
for the exact commands and failures.

## Native association contract

- Android declares verified HTTPS intents for `natalopetshop.com` and
  `www.natalopetshop.com`.
- iOS Associated Domains declares `applinks:natalopetshop.com` and
  `applinks:www.natalopetshop.com`.
- The AASA endpoint returns Team ID `87FXPV558A`, bundle ID
  `com.natalo.petshop`, and Feed (`/feed/*`), product (`/products/*`), and
  profile (`/u/*`) paths.
- `/.well-known/assetlinks.json` must be served by both production hosts with
  the Android package and release signing certificate already checked by the
  association regression test.

## Share-content contract

- Shared URLs must be canonical HTTPS URLs on `www.natalopetshop.com`, never
  an API, staging, localhost, or app-local URL.
- Feed share text uses the author name and canonical URL only. It must not
  include the post caption.
- Product share text may include only the public product name, price, and URL.
- Profile share text may include only the public display name, username, and
  URL.
- Rich preview metadata remains server-side. Do not attach an image/video file
  to the native share sheet and do not emit `og:video`.
- OG image fetches accept only approved HTTPS image hosts and reject redirects,
  invalid types, oversized responses, and non-raster content.

## Production and device gates

- [ ] Deploy the web release before distributing a mobile build. Do not run
      local `npm run build` against an unconfirmed database because it invokes
      `prisma migrate deploy`.
- [ ] Confirm both hosts return HTTP 200, JSON content type, and no redirect:
      `https://natalopetshop.com/.well-known/assetlinks.json`,
      `https://www.natalopetshop.com/.well-known/assetlinks.json`,
      `https://natalopetshop.com/.well-known/apple-app-site-association`, and
      `https://www.natalopetshop.com/.well-known/apple-app-site-association`.
- [ ] Install a signed Android build on a physical device. Open Feed, product,
      and profile links while the app is terminated and while it is foregrounded.
      Each link must resolve exactly once to the intended screen.
- [ ] Install the iOS/TestFlight build on a physical device. Repeat the same
      terminated and foreground Universal Link checks. This cannot be built or
      verified on Windows.
- [ ] Send Feed photo/carousel/video, product, and profile links through
      WhatsApp on Android and iOS. Confirm title, description, image, domain,
      and deep-link destination; confirm no caption/private data leaks.
- [ ] Change a public preview asset once, share a link with a new `v` token,
      and confirm WhatsApp refreshes the card without stale metadata.
- [ ] On a non-public/deleted Feed post and an invalid product/profile link,
      confirm the browser shows the safe fallback/404 and exposes no private
      data.

## Release order

1. Merge the reviewed application and web changes, then let CI run the safe
   build in its confirmed database environment.
2. Deploy the web/AASA/assetlinks routes to both canonical production hosts.
3. Validate association endpoints and HTML metadata with public HTTPS requests.
4. Distribute signed Android and TestFlight iOS builds; complete the device
   deep-link matrix above.
5. Complete the WhatsApp preview matrix and cache-version refresh check.
6. Release only after every unchecked production/device gate is complete.
