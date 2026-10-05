# Web shortcut Lottie delivery

The home page uses the same eight approved animations as Flutter, with 40 px
slots. Mobile has four columns and two rows; desktop has eight columns.
Category, promotion, voucher, and loyalty links use the web app's routes.
Trending, House Call Grooming, and Dog Training links have been removed from
below the grid. Best sellers remain linked in their existing section.

`AnimatedShortcutIcon` starts loading within 180 px of the viewport, plays only
when actually visible, pauses on a hidden tab, and destroys the player on
unmount. It imports Lottie dynamically and respects the composition's 30 fps
with `setSubframe(false)`. Reduced motion shows a static SVG and initially skips
the player and animation download. Loading errors report to the console and
retain the static image. Lottie loads JSON asynchronously by its content-hashed
URL, using the browser's asset cache. Explicit image asset paths avoid duplicated
URL prefixes. Web delivery adds mask flags and named dash properties required
by the SVG player; the approved artwork and motion remain the same.

Build web assets from the approved Flutter source with:

```powershell
node scripts/build-shortcut-web-assets.cjs
```

The script creates WebP delivery images up to 384 px, preserves Lottie's original
coordinate dimensions, removes redundant samples inside motion holds, and
generates static SVG fallbacks. Artwork updates get content-hashed filenames
with immutable caching. Generated URLs are recorded in
`components/home/shortcut-assets.json`. The Flutter source assets are unchanged.
The script removes obsolete generated hashes inside its own output directory.

Measured delivery files: 1,007,623 bytes uncompressed (0.96 MiB), versus 6.22 MiB
of Flutter source assets. Gzipping JSON and SVG gives 308,862 bytes including
WebP images. These totals exclude the Lottie JavaScript library and other home
page resources; actual transfer depends on server/CDN compression and cache.

Validation:

```powershell
node node_modules/tsx/dist/cli.mjs --test tests/shortcut-lottie.test.ts
node node_modules/typescript/bin/tsc --noEmit --incremental false
node node_modules/eslint/bin/eslint.js components/home/AnimatedShortcutIcon.tsx app/page.tsx tests/shortcut-lottie.test.ts next.config.ts
```

Three tests passed: image/reference integrity and delivery size, playback and
cleanup lifecycle with mocked observers, and reduced-motion preference changes.
TypeScript passed. ESLint reported no errors and one existing ineffective
inline-disable warning in `app/page.tsx`.

After the user approved browser inspection, all eight icons rendered in the
local browser at a 390 x 844 mobile viewport. SVG frame changes confirmed motion,
including the voucher after fixing its dash metadata. Scrolling two pages below
the grid produced unchanged SVG frames for all eight players; returning to the
grid resumed motion. No new shortcut loading errors appeared after the fixes.
The mobile screenshot is `docs/web-shortcuts-mobile.jpg`.

This is local functional verification, not a measured frame-rate benchmark on
low-end phones. The local database was unavailable during inspection; product
sections used the existing fallback and Next.js displayed its development issue
badge. This change has not been deployed.
