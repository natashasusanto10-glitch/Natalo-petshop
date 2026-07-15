import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Membuka ringkasan perlindungan yang benar-benar tersedia di Natalo.
Future<void> showShoppingAssuranceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.topExtraLarge),
    builder: (_) => const _ShoppingAssuranceSheet(),
  );
}

class _ShoppingAssuranceSheet extends StatelessWidget {
  const _ShoppingAssuranceSheet();

  void _openRoute(BuildContext context, String route) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: AppRadius.pill,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Belanja Aman',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            'Perlindungan belanja yang tersedia di Natalo.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          const _AssuranceItem(
            icon: Icons.receipt_long_outlined,
            title: 'Pesanan dapat dipantau',
            description:
                'Pantau pembayaran dan status pesanan melalui Detail Pesanan.',
          ),
          const _AssuranceItem(
            icon: Icons.assignment_return_outlined,
            title: 'Pengembalian sesuai kebijakan',
            description:
                'Pengajuan pengembalian atau refund mengikuti kondisi dan ketentuan pesanan.',
          ),
          const _AssuranceItem(
            icon: Icons.event_available_outlined,
            title: 'Pembatalan sesuai status',
            description:
                'Pembatalan tersedia selama status dan pembayaran pesanan masih mengizinkan.',
          ),
          const _AssuranceItem(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Bantuan admin melalui chat',
            description:
                'Hubungi admin Natalo jika kamu membutuhkan bantuan terkait pesanan.',
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openRoute(context, '/chat'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Buka Chat'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _openRoute(context, '/kebijakan-pengembalian'),
              child: const Text('Lihat Kebijakan Pengembalian'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssuranceItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _AssuranceItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
