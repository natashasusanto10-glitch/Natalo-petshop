import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Chip toggle "soft tint" satu sumber — dipakai di filter Ulasan
/// (product_detail_screen) dan tag cepat form tulis ulasan
/// (member_reviews_screen). Sengaja BUKAN [ChoiceChip]: Material chip
/// selalu render checkmark bawaan saat selected, yang menutupi ikon custom
/// (bintang/foto) dan bikin state aktif terasa "hitam pekat". Di sini state
/// aktif = tint biru lembut + border, tanpa centang duplikat.
///
/// [selected] murni presentasi — parent yang menentukan apakah [onTap]
/// men-toggle (tap chip aktif → nonaktif lagi) atau set eksklusif.
class SoftToggleChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const SoftToggleChip({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? NataloColors.primary : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? NataloColors.primarySoft : cs.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? NataloColors.primary : cs.outlineVariant,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
