# Profile Grid and Public Header Design

## Goal

Modernize Natalo profile surfaces using the useful interaction patterns from
the supplied Instagram iPhone 15 Pro references while preserving Natalo's
colors, typography, navigation model, commerce tabs, and official identity.

## Scope

The work covers the signed-in member profile (`MemberScreen`) and another
user's public profile (`PublicProfileScreen`). It does not redesign post detail,
feed playback, profile editing, follow APIs, messaging APIs, or official-store
branding.

## Shared profile grid

- Both profile surfaces use one shared grid geometry contract.
- The grid is three columns and edge-to-edge, with no horizontal content
  padding, card margin, or tile corner radius.
- Tiles use a portrait 4:5 ratio (`childAspectRatio: 0.8`).
- Horizontal and vertical gaps are exactly 1 logical pixel.
- Media uses `BoxFit.cover`; existing video, commerce, moderation, and loading
  badges remain above the media in their current Natalo styling.
- Empty, loading, error, and pagination states retain their current behavior.
- The shared geometry must apply to Posts, Video, and Belanja content on both
  member and public profiles so tab switching never changes tile dimensions.

## Navigation by context

- The member's own profile retains Natalo's bottom navigation with Account
  selected.
- A public profile never renders a bottom navigation bar. Back navigation and
  the native iOS swipe-back gesture return to the previous screen.
- Public-profile navigation must not be wrapped in a shell that reintroduces
  the global bottom bar.

## Public profile header

### Expanded state

The public profile initially shows the existing user information: avatar,
display identity, post/follower/following statistics, bio, follow state,
message action where supported, and the existing secondary action. The header
respects the iPhone safe area and Dynamic Island through `MediaQuery`; it uses
no fixed status-bar offset.

### Collapsed state

As the user scrolls, the large profile information moves out naturally. A
compact pinned top bar remains with:

- back action on the left;
- public username/display handle as the primary title;
- overflow action on the right for another non-official user.

The overflow exposes only existing supported actions, including report, block,
and share where those actions currently exist. It must not advertise an action
without a working backend flow. Official profiles retain their existing Natalo
identity, safe colors, and verified treatment.

## Scroll-driven tab merge animation

The public profile's Posts, Video, and Belanja tabs start as a full-width pinned
row. During header collapse they merge into one compact segmented pill through
a smooth right-to-left motion.

- Animation is driven by normalized `shrinkOffset`; it does not use a timer or
  one-shot controller.
- Scroll progress `0.0`: full-width tab row beneath the expanded profile.
- Around `0.3`: the rightmost tab begins moving left and the container starts
  narrowing.
- Around `0.6`: all tabs converge, gaps decrease, corner radius increases, and
  optional labels fade without changing the active tab.
- Progress `1.0`: one compact segmented pill is pinned below the compact top
  bar.
- Reversing scroll reverses the same interpolation smoothly.
- Position, width, radius, internal spacing, and any label opacity use
  interpolation (`lerp`) from the same scroll progress.
- The grid's scroll position and first visible tile do not jump during the
  transition.
- Tap and horizontal swipe continue to use the existing `TabController` and
  preserve the selected tab.
- Motion respects reduced-motion accessibility. With reduced motion enabled,
  geometry changes directly with scroll without decorative overshoot or spring
  effects.

## Member profile header

The signed-in member profile keeps its existing Natalo hero/header and bottom
navigation. It receives only the shared 4:5 edge-to-edge grid geometry. The
public-profile collapsed header and tab-pill transformation are not applied to
the member profile.

## Interaction and accessibility

- Back, overflow, Follow/Following, Message, and each tab retain semantic
  labels and minimum usable touch targets.
- The active tab remains distinguishable through more than color alone.
- Header and tab foreground colors retain accessible contrast in light/dark
  themes and official-profile treatments.
- Loading or follow-action errors retain the current data and do not reset the
  selected tab or scroll position.

## Verification

- Unit/widget tests cover the shared grid constants: three columns, 4:5 ratio,
  and 1-pixel spacing.
- Widget tests verify member profile retains bottom navigation and public
  profile does not render it.
- Header tests exercise expanded, intermediate, and collapsed scroll states,
  including right-to-left geometry progression and reverse scrolling.
- Tests verify tab selection persists through the merge animation.
- Golden/widget checks use an iPhone 15 Pro-equivalent logical width and at
  least one smaller Android width to catch overflow.
- Manual QA covers safe area, swipe-back, overflow actions, all three tabs,
  empty/loading grids, official profiles, dark mode, and reduced motion.
