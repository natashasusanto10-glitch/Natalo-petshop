# Premium Toast (SnackBar → AppToast banner) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all Material `SnackBar` usages with a single premium, compact, overlay-based toast banner that auto-hides independently of navigation (fixing the "stuck snackbar" bug) and unifies notification styling app-wide.

**Architecture:** Extend the existing `AppToast` (lib/widgets/app_toast.dart), which already renders overlay-based toasts via `Overlay.of(context, rootOverlay: true)`. Add a new `AppToast.showBanner(...)` bottom-anchored, content-hugging glass card with a colored icon, optional subtitle, optional action, and a thin countdown bar. Because it lives in the root overlay (not a per-route `ScaffoldMessenger`), its auto-dismiss timer is never interrupted by `Navigator.push`/`pop` — eliminating the orphaned-snackbar bug found in the audit. Then migrate the 84 `ScaffoldMessenger...showSnackBar(...)` call sites across 30 files to `AppToast.showBanner`.

**Tech Stack:** Flutter, Dart. Reuses existing `NataloColors`, `AppHaptics`, `MotionPrefs`, `OverlayEntry`.

## Global Constraints

- Toast visual spec (locked with user via mockups):
  - Content-hug pill/card, centered horizontally, anchored bottom (above bottom nav), `borderRadius: 14`.
  - White surface (`Colors.white`), soft shadow, hairline border `0xFFECEFF3`. `maxWidth: 340` → long text ellipsis or wraps to max 2 lines.
  - Leading icon 19px, NO circle background, colored per kind.
  - Title 13px `w600` (`NataloColors.grey900`/`0xFF0F172A`); optional subtitle 11px `0xFF64748B`.
  - Optional action: text-only, `NataloColors.primary` (`0xFF1E5FBF`), 12px `w600`.
  - Thin countdown bar at bottom (height 2.5, color = kind accent) that animates width 100%→0 over the toast duration.
  - Default duration 3s. Slide-up + fade entrance (reuse `_CartToastView` motion); respect reduced-motion.
- Kind → icon + accent color mapping (single source of truth in code):
  - `success` → `Icons.check_circle_rounded`, green `NataloColors.successDark`
  - `info` → `Icons.info_outline_rounded`, blue `NataloColors.primary`
  - `warning` → `Icons.warning_amber_rounded`, amber `0xFFC98A12`
  - `error` → `Icons.error_rounded` / `Icons.warning_amber_rounded`, red `NataloColors.danger`
  - callers may override `icon` (e.g. cart → `Icons.shopping_bag_rounded`, copy → `Icons.copy_rounded`, undo → `Icons.delete_outline_rounded` with `info`/neutral).
- Overlay-based only. NEVER reintroduce `ScaffoldMessenger.showSnackBar` in migrated sites.
- Existing `AppToast.show` (top toast) and `AppToast.showCartAdded`/`showCartDeleted` (bottom glass) MUST keep working — do not break current callers. `showBanner` is additive.
- Kind inference during migration (when a site is plain `SnackBar(content: Text(m))`): message contains "gagal"/"tidak bisa"/"error" (case-insensitive) → `error`; contains "berhasil"/"tersimpan"/"ditambahkan"/"disalin" → `success`; else → `info`. When ambiguous, prefer `info`. Document the chosen kind inline if non-obvious.
- Do not change message copy during migration (keep exact strings) unless the task explicitly says so.
- Every migrated file must still `flutter analyze` clean and drop any now-unused imports.

---

## File Structure

- `lib/widgets/app_toast.dart` — add `showBanner` static + `_BannerToastView` stateful widget (countdown + slide/fade). Keep all existing APIs. This file owns the toast system.
- 30 migration files under `lib/screens/`, `lib/widgets/`, `lib/features/`, `lib/utils/` — each swaps its `showSnackBar` calls for `AppToast.showBanner`. No new files.
- `test/widgets/app_toast_banner_test.dart` — NEW. Widget tests for the banner engine (renders, auto-dismisses, action fires, countdown present).

Migration is batched by feature area so each task is independently testable/reviewable. Batches:
1. Engine (Task 1) — the `showBanner` API + tests.
2. High-risk sites (Task 2) — the 6 confirmed-bug sites.
3. Medium-risk sites (Task 3) — the 3 action-navigates sites.
4. Auth & onboarding (Task 4) — login, login_otp, register, forgot_password.
5. Member area A (Task 5) — member_order_detail, member_orders, member_reviews, member_addresses.
6. Member area B + account (Task 6) — member_loyalty (remaining), member_vouchers, account_security, notification_preferences, notifications, profile_qr.
7. Commerce + feed + misc (Task 7) — checkout, product_detail, order_success (remaining), feed_screen, feed_new_post_screen, feed_video_post_view, public_profile*, favorite_button, post_likers_sheet, voice_search_modal, address_autocomplete_field, read_only_mode, main_navigation_screen.
8. Final sweep + verify (Task 8) — grep guard, full analyze, review.

---

### Task 1: Toast banner engine (`AppToast.showBanner`)

**Files:**
- Modify: `lib/widgets/app_toast.dart`
- Test: `test/widgets/app_toast_banner_test.dart`

**Interfaces:**
- Consumes: existing `ToastKind` enum, `AppHaptics`, `MotionPrefs`, `NataloColors`.
- Produces (called by all migration tasks):
  ```dart
  static void showBanner(
    BuildContext context,
    String message, {
    String? subtitle,
    ToastKind kind = ToastKind.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  })
  ```

- [ ] **Step 1: Write the failing test**

Create `test/widgets/app_toast_banner_test.dart`:

```dart
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/app_toast.dart';

Widget _host(void Function(BuildContext) onReady) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onReady(context));
            return const SizedBox.expand();
          },
        ),
      ),
    );

void main() {
  testWidgets('showBanner renders message + action and fires onAction',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host((context) {
      AppToast.showBanner(
        context,
        'Voucher berhasil ditukar!',
        subtitle: 'Cek di Voucher Member',
        kind: ToastKind.success,
        actionLabel: 'Lihat',
        onAction: () => tapped = true,
      );
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Voucher berhasil ditukar!'), findsOneWidget);
    expect(find.text('Cek di Voucher Member'), findsOneWidget);
    expect(find.text('Lihat'), findsOneWidget);

    await tester.tap(find.text('Lihat'));
    await tester.pump();
    expect(tapped, isTrue);

    // Let it auto-dismiss so the test's timers drain.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('showBanner auto-dismisses after duration', (tester) async {
    await tester.pumpWidget(_host((context) {
      AppToast.showBanner(context, 'Kode disalin',
          kind: ToastKind.success,
          duration: const Duration(milliseconds: 600));
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Kode disalin'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // duration
    await tester.pump(const Duration(milliseconds: 400)); // reverse anim
    await tester.pump(const Duration(milliseconds: 400)); // removal delay
    expect(find.text('Kode disalin'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/widgets/app_toast_banner_test.dart`
Expected: FAIL — `showBanner` is not defined on `AppToast`.

- [ ] **Step 3: Add the `showBanner` static to `AppToast`**

In `lib/widgets/app_toast.dart`, inside `class AppToast`, add (after `showCartDeleted`):

```dart
  /// Premium bottom banner — content-hug glass card dengan ikon berwarna,
  /// subtitle + aksi opsional, dan garis hitung-mundur. Overlay-based (root)
  /// jadi auto-hide TIDAK terganggu Navigator.push/pop — pengganti aman untuk
  /// SnackBar Material yang bisa "nyangkut" saat pindah route.
  static void showBanner(
    BuildContext context,
    String message, {
    String? subtitle,
    ToastKind kind = ToastKind.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _BannerToastView(
        message: message,
        subtitle: subtitle,
        kind: kind,
        icon: icon,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
    overlay.insert(entry);
    _doHaptic(kind);
    Future.delayed(duration + const Duration(milliseconds: 650), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }
```

- [ ] **Step 4: Add the `_BannerToastView` widget**

Append to `lib/widgets/app_toast.dart` (top-level, after `_ToastViewState`):

```dart
class _BannerToastView extends StatefulWidget {
  final String message;
  final String? subtitle;
  final ToastKind kind;
  final IconData? icon;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _BannerToastView({
    required this.message,
    required this.subtitle,
    required this.kind,
    required this.icon,
    required this.duration,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  State<_BannerToastView> createState() => _BannerToastViewState();
}

class _BannerToastViewState extends State<_BannerToastView>
    with TickerProviderStateMixin {
  late final AnimationController _inOut;
  late final AnimationController _countdown;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _inOut = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _inOut, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero)
        .animate(CurvedAnimation(parent: _inOut, curve: Curves.easeOutCubic));
    _countdown = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _inOut.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _inOut.reverse();
    });
  }

  @override
  void dispose() {
    _inOut.dispose();
    _countdown.dispose();
    super.dispose();
  }

  ({Color accent, IconData icon}) _kindStyle() {
    switch (widget.kind) {
      case ToastKind.success:
        return (accent: NataloColors.successDark, icon: Icons.check_circle_rounded);
      case ToastKind.warning:
        return (accent: const Color(0xFFC98A12), icon: Icons.warning_amber_rounded);
      case ToastKind.error:
        return (accent: NataloColors.danger, icon: Icons.error_rounded);
      case ToastKind.info:
        return (accent: NataloColors.primary, icon: Icons.info_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduce(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final style = _kindStyle();
    final iconData = widget.icon ?? style.icon;

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onAction,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFECEFF3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: widget.actionLabel != null ? 4 : 12,
                    top: 10,
                    bottom: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconData, color: style.accent, size: 19),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.message,
                              maxLines: widget.subtitle == null ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  height: 1.25,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            widget.actionLabel!,
                            style: TextStyle(
                              color: NataloColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  height: 2.5,
                  child: AnimatedBuilder(
                    animation: _countdown,
                    builder: (context, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1 - _countdown.value,
                      child: Container(color: style.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset + 84,
      child: IgnorePointer(
        ignoring: widget.onAction == null,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SlideTransition(
                position:
                    reduce ? const AlwaysStoppedAnimation(Offset.zero) : _slide,
                child: FadeTransition(opacity: _opacity, child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd flutter_app && flutter test test/widgets/app_toast_banner_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Analyze**

Run: `cd flutter_app && flutter analyze lib/widgets/app_toast.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/widgets/app_toast.dart flutter_app/test/widgets/app_toast_banner_test.dart
git commit -m "feat(toast): AppToast.showBanner premium compact banner engine"
```

---

### Task 2: Migrate 6 High-risk sites (confirmed stuck-bug)

**Files:**
- Modify: `lib/screens/cart_screen.dart:716`, `lib/screens/register_screen.dart:289`, `lib/screens/order_success_screen.dart:877`, `lib/widgets/moderation_action_sheet.dart` (3 sites: ~152, ~217, ~278)

**Interfaces:**
- Consumes: `AppToast.showBanner` (Task 1).

For each site, replace the `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` with `AppToast.showBanner(...)`. Add `import '../widgets/app_toast.dart';` (or correct relative path) if absent. Remove now-unused `ScaffoldMessenger` usage. Keep exact message strings.

- [ ] **Step 1: cart_screen.dart:716 — login-required before checkout**

Replace:
```dart
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (!memberStore.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masuk member dulu untuk lanjut checkout.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pushNamed(
```
with:
```dart
    if (!memberStore.isLoggedIn) {
      AppToast.showBanner(
        context,
        'Masuk member dulu untuk lanjut checkout.',
        kind: ToastKind.info,
      );
      Navigator.pushNamed(
```
(Confirm `import '../widgets/app_toast.dart';` present; add if missing.)

- [ ] **Step 2: register_screen.dart:289 — account created (no welcome voucher)**

Replace the `ScaffoldMessenger...showSnackBar(SnackBar(content: Text('Akun berhasil dibuat...')))` with:
```dart
      AppToast.showBanner(context, '<exact original message>',
          kind: ToastKind.success);
```
(Read the exact string at that line first and preserve it verbatim.)

- [ ] **Step 3: order_success_screen.dart:877 (`_showProductSnack`) — recommended product**

Read the method. Replace its `ScaffoldMessenger...showSnackBar(...)` body with an `AppToast.showBanner(context, <message>, kind: ToastKind.info)`. Ensure the toast is shown BEFORE `Navigator.pushNamed('/product-detail', ...)` returns is irrelevant now (overlay survives), but keep call order as-is.

- [ ] **Step 4: moderation_action_sheet.dart (3 sites)**

For each of the 3 sites (self-delete ~152, block user ~217, report submit ~278): the pattern is `Navigator.of(context).pop(...)` then `showSnackBar`. Capture the messenger BEFORE pop is no longer needed — replace with `AppToast.showBanner(rootContext, <message>, kind: ...)` where `rootContext` is a context that outlives the sheet. Since `showBanner` uses `Overlay.of(context, rootOverlay: true)`, pass the sheet's `context` BEFORE the `pop`, OR capture `final overlayContext = Navigator.of(context, rootNavigator: true).context;` before popping and pass that. Use kind: delete/block → `success` if worded as done, `error` on failure; report → `success`.

Concretely for self-delete (~152):
```dart
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop(ModerationActionResult(...));
    AppToast.showBanner(rootCtx, '<exact message>', kind: ToastKind.success);
```

- [ ] **Step 5: Analyze the 4 files**

Run: `cd flutter_app && flutter analyze lib/screens/cart_screen.dart lib/screens/register_screen.dart lib/screens/order_success_screen.dart lib/widgets/moderation_action_sheet.dart`
Expected: No issues (fix any unused-import warnings by removing dead imports).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(toast): migrate 6 high-risk stuck-snackbar sites to AppToast.showBanner"
```

---

### Task 3: Migrate 3 Medium-risk sites (action navigates)

**Files:**
- Modify: `lib/screens/member_loyalty_screen.dart:168`, `lib/screens/member_vouchers_screen.dart:429`, `lib/widgets/favorite_button.dart:117`

**Interfaces:** Consumes `AppToast.showBanner`.

- [ ] **Step 1: member_loyalty_screen.dart:168 — voucher claim success (the reported screenshot)**

Replace:
```dart
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voucher ${result.code} berhasil ditukar! Cek di Voucher Member.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => Navigator.pushNamed(context, '/member/vouchers'),
          ),
        ),
      );
```
with:
```dart
      AppToast.showBanner(
        context,
        'Voucher ${result.code} berhasil ditukar!',
        subtitle: 'Cek di Voucher Member',
        kind: ToastKind.success,
        actionLabel: 'Lihat',
        onAction: () => Navigator.pushNamed(context, '/member/vouchers'),
      );
```

- [ ] **Step 2: member_loyalty_screen.dart:183 — claim error (same file, second SnackBar)**

Replace the `'Gagal menukar poin: $error'` SnackBar with:
```dart
      AppToast.showBanner(context, 'Gagal menukar poin. Coba lagi.',
          kind: ToastKind.error);
```

- [ ] **Step 3: member_vouchers_screen.dart:429 — copy code**

Replace with `AppToast.showBanner(context, '<exact message>', kind: ToastKind.success, icon: Icons.copy_rounded, actionLabel: <existing label or null>, onAction: <existing nav or null>)`. Read exact strings first.

- [ ] **Step 4: favorite_button.dart:117 (+ 130, 139 in same file) — wishlist toggles / login**

Migrate all 3 SnackBars in this file. Login-required → `kind: info` with `actionLabel: 'Masuk'`. Added/removed wishlist → `kind: success`, `icon: Icons.favorite_rounded`.

- [ ] **Step 5: Analyze + Commit**

Run: `cd flutter_app && flutter analyze lib/screens/member_loyalty_screen.dart lib/screens/member_vouchers_screen.dart lib/widgets/favorite_button.dart`
Expected: No issues.
```bash
git add -A
git commit -m "fix(toast): migrate 3 medium-risk action-nav snackbars"
```

---

### Task 4: Migrate auth & onboarding

**Files:**
- Modify: `lib/screens/login_screen.dart` (3), `lib/screens/login_otp_screen.dart` (5), `lib/screens/register_screen.dart` (remaining 4), `lib/screens/forgot_password_screen.dart` (2)

**Interfaces:** Consumes `AppToast.showBanner`.

- [ ] **Step 1:** For each of the 14 sites, read the exact message + any `duration`/`action`. Replace `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), ...))` with `AppToast.showBanner(context, m, kind: <inferred>)`. Preserve any `SnackBarAction` as `actionLabel`/`onAction`. Apply the kind-inference rule from Global Constraints.
- [ ] **Step 2:** Where a captured `messenger` var was used (e.g. `messenger.showSnackBar`), replace with `AppToast.showBanner(context, ...)` and delete the now-unused `messenger` local if it has no other use.
- [ ] **Step 3: Analyze** each file; remove unused imports.
  Run: `cd flutter_app && flutter analyze lib/screens/login_screen.dart lib/screens/login_otp_screen.dart lib/screens/register_screen.dart lib/screens/forgot_password_screen.dart`
  Expected: No issues.
- [ ] **Step 4: Commit** `git commit -am "fix(toast): migrate auth & onboarding snackbars"`

---

### Task 5: Migrate member area A

**Files:**
- Modify: `lib/screens/member_order_detail_screen.dart` (11), `lib/screens/member_orders_screen.dart` (1), `lib/screens/member_reviews_screen.dart` (7), `lib/screens/member_addresses_screen.dart` (5)

**Interfaces:** Consumes `AppToast.showBanner`.

Note: `member_order_detail_screen.dart:3797` and `member_orders_screen.dart:1752` are top-level helper functions `void _showSnack(BuildContext, String)` used by many callers. Migrate the helper body to `AppToast.showBanner(context, message, kind: ...)` — this fixes multiple call sites at once. If the helper cannot infer kind, add a `ToastKind kind = ToastKind.info` param and pass at call sites that mean success/error.

- [ ] **Step 1:** Migrate the shared `_showSnack` helpers first (both files) to call `AppToast.showBanner`. Add optional `ToastKind` param.
- [ ] **Step 2:** Migrate remaining direct `showSnackBar` sites in each file per the standard pattern + kind inference.
- [ ] **Step 3: Analyze** the 4 files; remove unused imports.
  Run: `cd flutter_app && flutter analyze lib/screens/member_order_detail_screen.dart lib/screens/member_orders_screen.dart lib/screens/member_reviews_screen.dart lib/screens/member_addresses_screen.dart`
  Expected: No issues.
- [ ] **Step 4: Commit** `git commit -am "fix(toast): migrate member order/review/address snackbars"`

---

### Task 6: Migrate member area B + account/settings

**Files:**
- Modify: `lib/screens/member_vouchers_screen.dart` (remaining if any), `lib/screens/account_security_screen.dart` (7), `lib/screens/notification_preferences_screen.dart` (3), `lib/screens/notifications_screen.dart` (2), `lib/screens/profile_qr_screen.dart` (1)

**Interfaces:** Consumes `AppToast.showBanner`.

- [ ] **Step 1:** Migrate each site per standard pattern + kind inference. `account_security_screen.dart` uses captured `messenger` locals at lines 138/146/198/207 — replace with `AppToast.showBanner(context, ...)` and drop unused `messenger` vars.
- [ ] **Step 2: Analyze** the files; remove unused imports.
  Run: `cd flutter_app && flutter analyze lib/screens/account_security_screen.dart lib/screens/notification_preferences_screen.dart lib/screens/notifications_screen.dart lib/screens/profile_qr_screen.dart`
  Expected: No issues.
- [ ] **Step 3: Commit** `git commit -am "fix(toast): migrate account & notification snackbars"`

---

### Task 7: Migrate commerce + feed + misc

**Files:**
- Modify: `lib/screens/checkout_screen.dart` (5), `lib/screens/product_detail_screen.dart` (3), `lib/screens/order_success_screen.dart` (remaining 2), `lib/screens/feed_screen.dart` (1), `lib/screens/feed_new_post_screen.dart` (1), `lib/features/feed/widgets/feed_video_post_view.dart` (1), `lib/screens/public_profile_screen.dart` (1), `lib/screens/public_profile_follow_list_screen.dart` (1), `lib/widgets/post_likers_sheet.dart` (1), `lib/widgets/voice_search_modal.dart` (1), `lib/widgets/address_autocomplete_field.dart` (1), `lib/utils/read_only_mode.dart` (1), `lib/screens/main_navigation_screen.dart` (1)

**Interfaces:** Consumes `AppToast.showBanner`.

- [ ] **Step 1:** Migrate each site per standard pattern + kind inference. Special cases:
  - `read_only_mode.dart` → `kind: warning` ("mode hanya-lihat").
  - `main_navigation_screen.dart` double-back-to-exit → `kind: info`; drop the preceding `messenger.hideCurrentSnackBar()` (overlay toasts don't stack the same way; if rapid double-taps are a concern, showBanner naturally replaces via short duration — no hide needed). Verify the exit-on-second-back logic still triggers.
  - `checkout_screen.dart:880` had `duration: seconds: 5` → pass `duration: const Duration(seconds: 5)`.
- [ ] **Step 2: Analyze** all files in this task; remove unused imports.
- [ ] **Step 3: Commit** `git commit -am "fix(toast): migrate commerce, feed & misc snackbars"`

---

### Task 8: Final sweep + verification

**Files:** repo-wide check; no functional change expected.

- [ ] **Step 1: Guard grep — no `showSnackBar` left**

Run: `cd flutter_app && grep -rn "showSnackBar" lib/ || echo CLEAN`
Expected: `CLEAN` (zero matches). If any remain, migrate them (repeat Task-7 pattern) and re-run.

- [ ] **Step 2: Guard grep — no leftover `SnackBar(` / `SnackBarAction(`**

Run: `cd flutter_app && grep -rn "SnackBar(\|SnackBarAction(" lib/ || echo CLEAN`
Expected: `CLEAN`. (The `snackBarTheme` in `lib/theme/app_theme.dart` may remain — that's a theme definition, not a usage; leave it or note it as dead. If removing, do it here and analyze.)

- [ ] **Step 3: Full analyze**

Run: `cd flutter_app && flutter analyze`
Expected: No new issues introduced by this migration.

- [ ] **Step 4: Full test suite for touched areas**

Run: `cd flutter_app && flutter test test/widgets/app_toast_banner_test.dart`
Expected: PASS. Also run any existing screen tests that pump migrated screens to ensure no regression:
`cd flutter_app && flutter test` (or a targeted subset if full run is too slow).

- [ ] **Step 5: Commit any cleanup**

```bash
git commit -am "chore(toast): final sweep — remove dead SnackBar theme/imports" || echo "nothing to commit"
```

---

## Self-Review Notes

- Spec coverage: engine (Task 1) implements every locked visual constraint; Tasks 2–7 cover all 84 sites across 30 files; Task 8 guards completeness via grep.
- The 3 confirmed bug categories (show-then-push, push-then-show, pop-then-show) are all fixed structurally because the toast lives in the root overlay with an independent timer.
- Kind inference is documented once (Global Constraints) and referenced by each migration task — no per-site guesswork left undefined.
- Device-verify remains pending (no web preview for Flutter): confirm on real device that toasts appear above the bottom nav, auto-hide, and no longer stick across navigation.
