# Task 1 Report: Merged tab presentation motion

## Status

Complete. The motion model now represents the expanded icon-only state and the collapsed merged-tab state.

## Changes

- `labelOpacity` now transitions monotonically from `0` (expanded) to `1` (collapsed).
- Added `surfaceOpacity`, transitioning from `0` to `1` for the merged dark capsule surface.
- Added `underlineOpacity`, transitioning from `1` to `0` as the expanded underline disappears.
- Preserved the existing right-to-left alignment, width, corner radius, and gap interpolation.
- Equality and hash code include the new presentation fields.

## Tests / output

Command: `cd flutter_app; flutter test test/widgets/public_profile_header_motion_test.dart`

Result: all 5 tests passed.

## Self-review

Endpoint values and intermediate smoothstep values are covered. Reverse-scroll determinism and clamping remain unchanged. No unrelated files were staged or modified by this task.

## Concerns

The widget consuming this model must apply the new opacities to its surface, labels, and underline. This task intentionally changes only the motion contract and its tests.

## Commit

`feat(profile): animate merged tab presentation`
