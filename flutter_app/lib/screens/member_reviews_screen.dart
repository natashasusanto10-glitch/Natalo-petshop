import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Ulasan Saya — daftar review produk yang user submit + reviewable items
/// (produk yang sudah delivered tapi belum di-review).
class MemberReviewsScreen extends StatelessWidget {
  const MemberReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          title: const Text('Ulasan Saya'),
          backgroundColor: const Color(0xFFF7FAFF),
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Belum Ditulis'),
              Tab(text: 'Sudah Ditulis'),
            ],
            labelColor: NataloColors.primary,
            unselectedLabelColor: NataloColors.textSecondary,
            indicatorColor: NataloColors.primary,
          ),
        ),
        body: TabBarView(
          children: [
            _EmptyReviewState(
              icon: Icons.edit_note_rounded,
              iconColor: const Color(0xFFD97706),
              iconBg: const Color(0xFFFEF3C7),
              title: 'Tidak ada produk yang perlu di-ulas',
              subtitle:
                  'Setelah pesanan selesai (DELIVERED), produk yang belum di-review akan muncul di sini.',
              ctaLabel: 'Lihat Pesanan',
              onAction: () => Navigator.pushReplacementNamed(
                context,
                '/member/orders',
              ),
            ),
            const _EmptyReviewState(
              icon: Icons.rate_review_outlined,
              iconColor: Color(0xFFEC4899),
              iconBg: Color(0xFFFCE7F3),
              title: 'Belum ada ulasan',
              subtitle:
                  'Ulasan produk Anda akan muncul di sini setelah submit. Bonus 5 poin per review approved!',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReviewState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onAction;

  const _EmptyReviewState({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 44, color: iconColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            if (ctaLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onAction,
                child: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
