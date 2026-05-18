import 'package:flutter/material.dart';

/// Natalo Petshop border radius system.
///
/// New UI should use these tokens instead of hardcoded radius values.
class AppRadius {
  AppRadius._();

  /// 8px: badges, chips, small controls.
  static const double sm = 8;

  /// 12px: cards, search bars, compact buttons.
  static const double md = 12;

  /// 16px: large cards and primary buttons.
  static const double lg = 16;

  /// 20px: hero cards, dialogs, bottom sheets.
  static const double xl = 20;

  /// 28px: floating bottom nav shells and large soft surfaces.
  static const double xxl = 28;

  /// 999px: pills, avatars, fully rounded controls.
  static const double full = 999;

  static BorderRadius get small => BorderRadius.circular(sm);

  static BorderRadius get medium => BorderRadius.circular(md);

  static BorderRadius get large => BorderRadius.circular(lg);

  static BorderRadius get extraLarge => BorderRadius.circular(xl);

  static BorderRadius get extraExtraLarge => BorderRadius.circular(xxl);

  static BorderRadius get pill => BorderRadius.circular(full);

  static BorderRadius get topMedium => const BorderRadius.vertical(
        top: Radius.circular(md),
      );

  static BorderRadius get topLarge => const BorderRadius.vertical(
        top: Radius.circular(lg),
      );

  static BorderRadius get topExtraLarge => const BorderRadius.vertical(
        top: Radius.circular(xl),
      );

  static BorderRadius get bottomMedium => const BorderRadius.vertical(
        bottom: Radius.circular(md),
      );
}
