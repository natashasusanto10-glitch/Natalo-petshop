# Natalo shortcut animations

Eight approved designs are exported to `flutter_app/assets/lottie/shortcuts/`
and used by `AnimatedShortcutIcon` in the home screen's existing 4 × 2 grid.
Navigation destinations and catalog filters are retained.

## Files and playback

| Asset | Artwork | Loop duration |
| --- | --- | --- |
| cat-food.json | Coral cat bowl, falling kibble | 3.2 s |
| dog-food.json | Golden dog bowl, falling kibble | 3.2 s |
| fish-food.json | Teal jar, unscrewing cap, pouring pellets | 4 s |
| medicine.json | Orange tube, green bottle, tablets and gel | 4.2 s |
| promo.json | Red flame and gold percent symbol | 2.9 s |
| new-products.json | Multicolor product grid and central NEW badge | 4.1 s |
| voucher.json | Violet discount ticket and teal delivery truck | 5 s |
| points.json | NL Point coin, red gift, emerging reward card | 5 s |

These are native Lottie compositions with a mixture of vector shapes and
approved transparent PNG artwork. Keep the PNGs alongside the JSON files;
the JSON files alone are not self-contained. No WebView or network is needed.
Small voucher/reward text is omitted to match the approved compact preview.
NEW is outlined so it does not depend on fonts installed on the phone.

All visible icons repeat at a composition frame rate of 30 fps. App background,
disabled TickerMode, and off-screen visibility pause playback. The app's
reduce-motion preference and OS accessibility setting display meaningful
static frames instead. Loading failures are reported and show fallback icons.

## Rebuild assets

From the repository root with its Node dependencies installed:

```powershell
node flutter_app/tool/shortcut_export/export.cjs
```

`sources/` contains the approved HTML animation definitions. The converter reads
those local definitions using a small DOM shim and samples CSS/JavaScript
motion, with no browser execution. It supports only the SVG subset used here;
unsupported path commands and colors fail explicitly. It also reconstructs
the bottle corner hidden behind the tube cap in the flattened artwork.

`text-outlines.json` contains vector glyph outlines, so rebuilding is portable.
Regenerate it only when changing the text/font, on Windows with Impact and
Segoe UI installed:

```powershell
& flutter_app/tool/shortcut_export/text-outlines.ps1
```

## Verification — 2026-10-04

From `flutter_app/`:

```powershell
flutter analyze --no-pub lib/widgets/animated_shortcut_icon.dart lib/screens/home_screen.dart test/widgets/animated_shortcut_icon_test.dart
flutter test --no-pub test/widgets/animated_shortcut_icon_test.dart
flutter test --no-pub test/screens/home_screen_snapshot_test.dart
```

Results: no analyzer issues; 2 animation tests and 4 existing home tests passed.
All compositions loaded without warnings or missing images and rendered at
four points in their timelines. Visual evidence is `docs/shortcut-contact-sheet.png`
in the repository root: columns follow the table order, rows are 0%, 35%, 65%,
and 90% of each loop. Voucher is intentionally invisible on its entry frame.

Regenerate the contact sheet with:

```powershell
flutter test --no-pub test/widgets/animated_shortcut_icon_test.dart --dart-define=SHORTCUT_CONTACT_SHEET=../docs/shortcut-contact-sheet.png
```

Rendering was checked in Flutter widget tests. Device GPU performance and
Android/iOS release builds have not been tested or deployed in this task.
