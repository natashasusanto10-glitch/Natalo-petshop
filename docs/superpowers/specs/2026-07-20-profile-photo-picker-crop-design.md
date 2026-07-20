# Profile photo picker — Instagram-style crop + collapsing preview

Date: 2026-07-20

## Problem

The current "Ubah Foto Profil" flow ([update_profile_photo_sheet.dart](../../../flutter_app/lib/widgets/update_profile_photo_sheet.dart)) hands the "Pilih dari Galeri" tap straight to `ImagePicker.pickImage(source: gallery)` — the OS native picker. There is no in-app crop step: whatever aspect the OS returns is uploaded as-is, and the user has no way to reposition or zoom before committing.

Reference: screenshots of Instagram's own "Edit picture" flow — tap library, pinch-to-crop a photo inside a circular mask, smooth preview transitions as the gallery grid scrolls.

This app already has a full Instagram-style media picker for feed posts ([feed_media_picker_screen.dart](../../../flutter_app/lib/screens/feed_media_picker_screen.dart)) with a perf-tuned pinch/pan crop (`_PhotoCropTransform` + `_PhotoCropPreview`) and an isolate-based crop/export pipeline. This design reuses that machinery for profile photos instead of building new gesture/crop code.

## Goals

- Replace the "Pilih dari Galeri" path with a full-screen picker: grid of device photos + a live crop preview.
- Crop preview: square frame with a circular dim mask (Instagram-style), pinch/pan to reposition, 1:1 finger tracking, no lag.
- Preview area collapses smoothly into a small pinned circular thumbnail as the user scrolls the grid, and expands back only when scrolling back to the top (PINNED-only, matching the app's existing `CollapsingHeaderDelegate` used on Beranda/Produk — not floating/reveal-mid-scroll).
- Camera capture and "Hapus Foto" stay exactly as they are today — no crop step added to those paths.

## Non-goals

- No multi-photo/carousel selection (profile photo is always exactly one photo).
- No video support.
- No changes to the feed posting flow's behavior — only its crop code is relocated, not altered.

## Architecture

### Shared crop machinery (extracted, not duplicated)

`feed_media_picker_screen.dart` currently defines three private pieces used only by itself. They're extracted to `flutter_app/lib/widgets/photo_crop/`:

- `photo_crop_transform.dart` — `PhotoCropTransform` (public rename of `_PhotoCropTransform`), the `ChangeNotifier` holding scale + offset-fraction, unchanged behavior.
- `photo_crop_preview.dart` — `PhotoCropPreview` (public rename of `_PhotoCropPreview`), the pinch/pan gesture widget. Gains one new optional parameter, `overlayBuilder(BuildContext, Size frameSize) -> Widget?`, rendered above the image inside the same `ClipRect`/`Stack` (feed picker passes `null`; profile picker passes the circular dim-mask painter). Its **gesture engine is upgraded** (see "Pinch/pan crop behavior" below) — this is a shared change, so the feed picker inherits the improved feel too, and its existing tests must keep passing (regression gate).
- `photo_crop_export.dart` — the top-level `_processPhotoInIsolate` function and its `_PhotoProcessArgs` class (renamed public: `processPhotoInIsolate` / `PhotoProcessArgs`), used via `compute()` by both callers. Already parameterized by `targetAspect`, `scale`, `offsetFraction`, `maxLongSide`, `jpegQuality` — no signature changes needed, just relocation.

`feed_media_picker_screen.dart` is updated to import these three from the new location instead of defining them locally. No behavioral change to the feed posting flow.

### New screen: `ProfilePhotoPickerScreen`

`flutter_app/lib/screens/profile_photo_picker_screen.dart`.

```
static Future<File?> open(BuildContext context)
```

Pushed as a `fullscreenDialog` route from the sheet's gallery tile. Returns the final cropped square JPEG `File`, or `null` if the user backs out.

Internally:
- `photo_manager` permission + album fetch + paged asset loading — same approach as the feed picker (`PhotoManager.requestPermissionExtend()`, `getAssetPathList`, `getAssetListPaged`), reused conceptually but written fresh for this screen since the selection model is simpler (single-select, photos only — porting the feed picker's multi-select/mode-locking/thumb-strip machinery would be dead weight here).
- On open, auto-previews the most recent photo (mirrors feed picker's `_loadMoreAssets(initial: true)` → `_setPreviewAsset`).
- Tapping any grid tile replaces the live preview (no "selected list" — whatever is in the crop frame when the user confirms is the result).
- Header: close (`X`, pops `null`) — title — confirm button (circle checkmark, enabled once a photo has loaded), visually matching `_MediaPickerHeader`'s style.
- Grid: 4-column, `photo_manager` thumbnails, simplified `_ProfileGalleryTile` (selection ring only — no order badges, no video icon/duration, since photos-only single-select needs none of that).

### Collapsing preview header

Preview lives in a `SliverPersistentHeader` using the existing `CollapsingHeaderDelegate` ([collapsing_header_delegate.dart](../../../flutter_app/lib/widgets/collapsing_header_delegate.dart)) — the same PINNED-only delegate Beranda and Produk already use. No new collapse mechanism.

- `maxHeight`: square frame, width ≈ 75% of screen (matches feed picker's preview sizing convention).
- `minHeight`: ~64px pinned circular thumbnail.
- `builder(context, t)`: diameter interpolates linearly with `t` (required by the delegate's contract — content height must be linear in `t`). The circular dim-mask overlay (rendered via `PhotoCropPreview`'s `overlayBuilder`) fades its opacity to 0 over the first quarter of the collapse range (`t: 0 → 0.25`) so the collapsed state reads as a plain small avatar, not a shrunken crop box.
- The grid `SliverGrid` sits immediately below in the same `CustomScrollView` — scrolling the grid is what drives `shrinkOffset`, identical mechanism to Beranda/Produk today. Crop-vs-scroll conflict is avoided by construction: the preview's `Listener` (see "Pinch/pan crop behavior") consumes all touches over the preview for cropping, while scroll/collapse is driven only by touches on the grid region below. The two gesture regions are disjoint — no arena arbitration.

### Pinch/pan crop behavior (upgraded engine)

The current engine (`GestureDetector.onScaleStart/Update` + hard-clamped offset) tests as "kurang berkelas" — four concrete gaps, all fixed here. This is the centerpiece of the work, not an inherited freebie.

**Gap 0 — two-finger gesture unreliable at start (highest priority).** `GestureDetector`'s scale recognizer competes in the gesture arena against the ancestor `Scrollable` (which drives the collapse). When two fingers land, the initial pinch is often lost to / delayed behind the vertical-drag recognizer. **Fix:** replace `GestureDetector` with a raw `Listener` (`onPointerDown/Move/Up/Cancel`). `Listener` receives pointer events unconditionally — it does not enter the arena — so multi-touch is detected from the first frame and never stolen by scroll. We track active pointers in a `Map<int, Offset>` and compute the centroid + mean radius ourselves.

Architectural consequence (clean, matches IG): **the preview area owns all its own touches (crop only); the grid below owns scroll (collapse).** Dragging on the photo repositions it; the header collapses only when the user scrolls the grid. No arena arbitration between crop and scroll because they occupy disjoint regions.

**Gap 1 — zoom not anchored to fingers / two-finger drag doesn't move the image.** Current code scales toward the frame center and only pans by `focalPointDelta`, so during a pinch the content drifts out from under the fingers. **Fix:** focal-point-anchored transform. Each move frame, keep the image point under the current centroid stationary while scale changes, using the zoom-about-a-point formula `newOffset = centroid - (centroid - oldOffset) * (newScale / oldScale)`, then add the centroid's own translation delta. Result: content stays glued to the fingers, and a pure two-finger drag translates the image 1:1.

**Gap 2 — no momentum.** Releasing stops dead. **Fix:** on the last pointer lifting, compute release velocity (from recent centroid samples) and run a fling via an `AnimationController` + friction simulation, updating `PhotoCropTransform.offsetFraction` each tick, decelerating naturally. Any new pointer-down cancels the in-flight animation.

**Gap 3 — rigid edges.** Offset is hard-clamped, so hitting a boundary halts abruptly. **Fix:** rubber-band. Allow limited over-drag past the clamp bounds with progressive resistance (offset beyond the limit is damped, e.g. `overshoot * 0.55`), then spring back to the valid bound on release via the same `AnimationController` (spring/ease curve). Fling that reaches a boundary hands off into the same spring-back.

**Responsiveness (Gap "nge-lag") — preserved from the current engine:**
- Only the `Transform` layer rebuilds per gesture frame, scoped via `ListenableBuilder` on `PhotoCropTransform` — the image/`ClipRect`/layout subtree does not rebuild.
- Source image decoded at a capped resolution (clamped 512–1920px, from frame size × 4× max zoom × device pixel ratio) instead of full sensor resolution — no GPU stall resampling a 12MP texture each frame.
- Scale + translate combined into one `Matrix4` per frame (single compositing layer).

`PhotoCropTransform` gains the velocity/animation plumbing (or a companion controller owns the `AnimationController`, keeping the notifier a plain data holder — decided at plan time). Clamp/rubber-band math lives in `PhotoCropPreview` where frame/base sizes are known.

### Export pipeline

On confirm: `processPhotoInIsolate` runs in a background isolate via `compute()` with `targetAspect: 1.0` (square) and `maxLongSide: 1024` (matches the existing camera path's 1024×1024 cap in `update_profile_photo_sheet.dart` — smaller than the feed picker's 2160, since avatars don't need that resolution). Same pipeline as feed: decode → bake EXIF orientation → crop to the pinch/pan transform's window → resize → encode JPEG (quality 88) → write to temp dir.

### Sheet integration

`update_profile_photo_sheet.dart`'s "Pilih dari Galeri" tile changes from calling `_picker.pickImage(source: gallery)` to:

```
final file = await ProfilePhotoPickerScreen.open(context);
if (file == null) return; // user backed out
await _uploadFile(file);
```

`_uploadFile(File file)` is a small extraction of the upload/persist/toast/error-handling body currently inside `_pickFromSource` (lines ~77–128), so camera and gallery share identical upload behavior — same `ApiException`/`ReadOnlyModeException`/generic-error handling, same success toast. The camera path becomes `_uploadFile(File(picked.path))` after its existing `ImagePicker.pickImage(source: camera)` call. "Hapus Foto" is untouched.

## Testing

- Widget test: `ProfilePhotoPickerScreen` opens, auto-previews the newest photo, tapping a different tile swaps the preview, confirm returns a `File`.
- Widget test: collapse math — `CollapsingHeaderDelegate` `builder(context, t)` produces the expected interpolated diameter and mask opacity at `t = 0, 0.25, 1`.
- Unit test: `processPhotoInIsolate` with `targetAspect: 1.0` produces a square output for a non-square source image (reuse/extend feed picker's existing crop-math tests if present).
- Unit test (crop-engine math, no real gestures): focal-anchor formula keeps a given image point fixed under a synthetic centroid across a scale change; rubber-band damping maps an over-drag to the expected damped offset; clamp bounds computed correctly at scale 1 and 4.
- Widget test: a two-pointer sequence on the preview via `WidgetTester.createGesture` (pointer down/move/up) updates `PhotoCropTransform` — asserts the `Listener` path fires without an ancestor scroll stealing it, and that a single-pointer drag on the grid still scrolls (regions disjoint).
- Regression: existing feed picker tests continue passing after the extraction + engine upgrade (the feed picker inherits the new engine — verify its crop-export output is unchanged for a fixed transform).
- Manual/device-verify (per project convention — most recent UI work in this repo is device-verify-pending): **two-finger detection reliability from the first touch**, zoom staying anchored to the fingers, fling momentum, rubber-band spring-back at edges, collapse feel while scrolling the grid, camera path unaffected. Verify on both a low-refresh (60Hz) and high-refresh device since `flutter_displaymode` is in play.

## Open questions / risks

- **Shared engine upgrade touches the feed picker.** Rewriting `PhotoCropPreview`'s gestures (arena `GestureDetector` → raw `Listener`, plus focal-anchor/fling/rubber-band) improves both surfaces but is the main regression surface. Mitigation: the feed picker's crop-export output for a fixed transform must be byte-stable in tests, and the feed posting flow is device-verified alongside the profile flow. If the shared rewrite proves too risky, fallback is to keep the feed picker on the old widget and add the new engine only to the profile picker (accepting temporary duplication) — but default is shared.
- **`Listener`-based multi-touch is hand-rolled.** We reimplement centroid/span/velocity that `ScaleGestureRecognizer` gave for free. This is deliberate (arena reliability), but the fling/rubber-band physics constants need device tuning to feel like IG — expect a tuning pass during device-verify, not a one-shot.
- Everything else confirmed during brainstorming (extraction approach, collapsing header + circular mask, grid/single-select/confirm, camera + delete untouched), including a visual mockup of the collapse behavior.
