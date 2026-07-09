/// Histeresis collapse header beranda (spec collapsing-header Jul 2026).
///
/// State BINER dengan dua ambang berbeda supaya header tidak flicker saat
/// scroll bolak-balik tipis di sekitar satu ambang: collapse baru terpicu
/// saat melewati [collapseAt] (default 72px), expand baru saat turun di
/// bawah [expandAt] (default 28px). Di zona antara keduanya state
/// dipertahankan.
///
/// Bounce iOS menghasilkan pixels NEGATIF — tidak pernah menyentuh ambang
/// collapse, jadi overscroll di puncak tidak memicu apa pun. Android modern
/// pakai stretch (pixels berhenti di 0) — aman tanpa cabang platform.
///
/// Fungsi murni supaya bisa di-unit-test tanpa widget tree — pola sama
/// dengan `chromeActionForScroll` di chrome_autohide.dart.
bool headerCollapsedFor({
  required double pixels,
  required bool currentlyCollapsed,
  double collapseAt = 72,
  double expandAt = 28,
}) {
  assert(expandAt < collapseAt, 'Histeresis butuh expandAt < collapseAt');
  if (!currentlyCollapsed && pixels > collapseAt) return true;
  if (currentlyCollapsed && pixels < expandAt) return false;
  return currentlyCollapsed;
}
