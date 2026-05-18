import 'package:flutter/material.dart';

/// Natalo Petshop spacing system based on a 4/8-point grid.
///
/// New UI should use these tokens instead of hardcoded spacing values.
class AppSpacing {
  AppSpacing._();

  /// 4px: tight icon/text gap, helper text gap, small badge padding.
  static const double xs = 4;

  /// 8px: small element gap, compact chip padding.
  static const double sm = 8;

  /// 12px: card/grid gap, small card padding, header-to-content gap.
  static const double md = 12;

  /// 16px: default screen padding and main card padding.
  static const double lg = 16;

  /// 20px: modal padding and larger component spacing.
  static const double xl = 20;

  /// 24px: default section spacing.
  static const double xxl = 24;

  /// 32px: major section separators and empty state padding.
  static const double xxxl = 32;

  /// 48px: hero/splash spacing.
  static const double giant = 48;

  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: lg,
  );

  static const EdgeInsets screenPadding = EdgeInsets.all(lg);

  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  static const EdgeInsets cardPaddingSmall = EdgeInsets.all(md);

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: xxl,
    vertical: md,
  );

  static const EdgeInsets modalPadding = EdgeInsets.all(xl);

  static const EdgeInsets bottomBarPadding = EdgeInsets.fromLTRB(
    lg,
    md,
    lg,
    md,
  );
}
