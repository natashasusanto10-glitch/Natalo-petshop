# Global Icon Clean Interaction Design

**Date:** 2026-07-22  
**Status:** Awaiting user review  
**Platform:** Flutter application (iOS and Android)

## 1. Objective

Standardize every interactive icon in the application so tapping or long-pressing it does not produce a visual tooltip, Material ripple, splash, highlight, or temporary background shape.

The change must preserve the icon's function, touch target, functional animation, and accessibility information.

## 2. Agreed User Experience

For every icon-only control in the application:

- A tap performs the existing action.
- A long press does not display a text tooltip.
- A press does not display a square, circular, or other colored backlight.
- A press does not produce an expanding Material ripple.
- The visible icon has no newly introduced permanent background.
- Existing functional animation remains, such as a heart pulse, bookmark state change, loading spinner, or page transition.
- VoiceOver and TalkBack can still identify the control and announce its purpose.

The result must be identical for iOS and Android unless a control already has an explicitly platform-native navigation behavior.

## 3. Scope

### 3.1 Included

This policy applies to all icon-only interactive controls, including icons implemented with:

- `IconButton`
- `InkResponse`
- `InkWell`
- `GestureDetector`
- custom widgets wrapping an icon, SVG, image glyph, or animated icon
- shared header, navigation, feed, commerce, profile, chat, order, and media controls

It applies whether the icon appears:

- directly on a screen
- over photo, carousel, or video media
- in an app bar or custom header
- in a bottom navigation bar
- in a modal, sheet, drawer, dialog, card, or list row
- in loading, empty, error, selected, or disabled states

### 3.2 Excluded

The following are not changed by this policy:

- text buttons and buttons containing both text and an icon
- cards, list rows, chips, tabs, product variants, and other non-icon controls
- intentional selected-state surfaces that remain visible after a tap
- functional feedback such as progress, loading, success, error, or state-change animation
- the time preview shown while actively scrubbing a video progress bar; this is interaction data, not a long-press icon tooltip
- operating-system feedback rendered outside the Flutter application

## 4. Tooltip Policy

All visual long-press tooltips associated with icon-only controls must be removed.

This includes:

- explicit `Tooltip` wrappers
- `tooltip:` values supplied to `IconButton` and related Material controls
- shared widget parameters whose only purpose is to display a visual tooltip

Removing a visual tooltip must not remove the accessible name of the control.

## 5. Accessibility Policy

Every interactive icon must retain an accessible semantic description.

The semantic node should provide, where applicable:

- `button: true`
- a concise Indonesian label describing the action
- selected, toggled, enabled, or disabled state
- an appropriate tap action

Examples of acceptable labels include `Bagikan`, `Simpan postingan`, `Keranjang`, `Kembali`, and `Tutup`.

Decorative icon children must not create duplicate screen-reader announcements. If the parent owns the semantic label, the child icon should be excluded or merged as appropriate.

No semantic label may be used as a reason to restore a visual tooltip. Semantics remain invisible unless an accessibility service is active.

## 6. Press-Feedback Policy

Every icon-only control must suppress Material press surfaces:

- splash color is transparent
- highlight color is transparent
- hover/focus/pressed overlay color does not paint a background behind the icon
- no rectangular or circular Material ink surface becomes visible during tap or long press

The touch target itself must remain available. Removing paint must not shrink the hit area.

Minimum target guidance:

- target at least 44 logical pixels on iOS-oriented layouts
- target at least 48 logical pixels where Material layout constraints apply
- visually small icons may use transparent padding to meet the target

Keyboard focus indication is an accessibility concern on desktop/web. If those platforms are supported, focus must remain discoverable without reintroducing the mobile press backlight. This may use a separate focus-only treatment.

## 7. Architecture

### 7.1 Recommended approach

Create or consolidate a shared icon interaction primitive that owns:

- tap handling
- semantic labeling and state
- transparent Material overlay behavior
- minimum touch target
- disabled behavior
- optional functional icon animation supplied by the caller

Existing shared icon components should delegate to this primitive where practical. Screen-specific widgets may remain when their layout or animation is unique, but must follow the same behavioral contract.

### 7.2 Why not use a global splash theme alone

A global `ThemeData` override is not sufficient because it could unintentionally remove useful feedback from text buttons, cards, list rows, and other non-icon controls. It also does not reliably remove explicit `Tooltip` wrappers.

The policy must therefore be enforced at the icon-control layer, with an audit of direct Material icon usages that bypass shared components.

## 8. Migration Rules

For each existing interactive icon:

1. Identify its visual tooltip source.
2. Move the tooltip text into an accessible semantic label if no equivalent label already exists.
3. Remove the visual tooltip mechanism.
4. Suppress splash, highlight, and pressed overlay paint.
5. Preserve the original callback, state behavior, debounce/throttle logic, and animation.
6. Preserve or restore an adequate transparent touch target.
7. Prevent duplicate semantic announcements.

The migration must not modify business logic, navigation destinations, API calls, or data state.

## 9. Feed Baseline

The Feed currently provides the clearest reproduction and acts as the baseline acceptance surface.

The following eight controls must comply:

- create post
- search
- cart
- like
- comment
- share
- save
- more options

The five action-rail controls share one implementation and must behave consistently for video, photo, and carousel posts.

## 10. Testing Strategy

### 10.1 Widget tests

Tests must verify that representative icon controls:

- have no `Tooltip` ancestor or tooltip property
- expose the expected semantic label
- remain tappable
- preserve selected/toggled semantics where relevant
- retain their expected touch target
- do not paint a Material overlay for pressed, hovered, or focused states covered by the component contract

Existing tests that locate controls with `find.byTooltip` must migrate to stable keys or semantics-based finders.

### 10.2 Regression coverage

At minimum, cover shared components used by:

- Feed top controls and action rail
- application headers
- bottom navigation
- product and cart actions
- profile and post controls
- chat and order controls
- modal/sheet close and action icons

### 10.3 Manual verification

Verify on both iOS and Android:

1. Tap each representative icon.
2. Press and hold each representative icon.
3. Confirm no label, ripple, square, circle, or backlight appears.
4. Confirm the action still runs once per tap.
5. Confirm state animations still run.
6. Enable VoiceOver or TalkBack and confirm the icon name and state are announced.

## 11. Acceptance Criteria

The work is accepted when:

- no icon-only control in the Flutter application displays a visual tooltip on long press
- no icon-only control displays a Material splash, ripple, highlight, or pressed background
- no icon action or navigation behavior changes
- functional animations remain intact
- all icon-only controls retain meaningful accessibility semantics
- touch targets remain usable and meet the stated minimum guidance
- video scrubber time preview remains available
- affected widget tests and static analysis pass
- manual checks pass on iOS and Android for the representative areas listed above

## 12. Non-Goals

This work does not redesign icon artwork, spacing, colors, navigation, button hierarchy, business flows, or non-icon press feedback. Any such changes require a separate specification.
