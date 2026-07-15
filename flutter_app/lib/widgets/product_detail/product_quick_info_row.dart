import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Baris informasi ringkas pada detail produk.
///
/// Tidak memberi card, border luar, atau warna baru agar menyatu dengan
/// permukaan halaman dan token visual Natalo yang sudah ada.
class ProductQuickInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback onTap;
  final String semanticLabel;

  const ProductQuickInfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    required this.semanticLabel,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailText = detail?.trim();

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (detailText != null && detailText.isNotEmpty)
                          TextSpan(
                            text: ' · $detailText',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
