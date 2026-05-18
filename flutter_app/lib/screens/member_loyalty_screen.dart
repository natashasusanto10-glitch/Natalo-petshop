import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Member Loyalty — show points balance, tier info, and CTA tukar poin.
class MemberLoyaltyScreen extends StatelessWidget {
  const MemberLoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Loyalty Natalo'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Riwayat poin',
            onPressed: () {
              AppHaptics.tap();
              Navigator.pushNamed(context, '/member/loyalty/history');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero card dengan total points
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  NataloColors.primary,
                  NataloColors.primaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: NataloColors.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Poin Natalo',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '0',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: -1,
                      ),
                    ),
                    SizedBox(width: 6),
                    Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'poin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Setiap belanja Rp10.000 = 1 poin',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Info cards: cara dapat poin
          const _InfoCard(
            icon: Icons.shopping_bag_outlined,
            iconColor: Color(0xFF7C3AED),
            iconBg: Color(0xFFEDE9FE),
            title: 'Belanja Produk',
            subtitle:
                'Setiap pembelian Rp10.000 dapat 1 poin. Berlaku setelah order DELIVERED.',
          ),
          const SizedBox(height: 10),
          const _InfoCard(
            icon: Icons.reviews_outlined,
            iconColor: Color(0xFFF59E0B),
            iconBg: Color(0xFFFEF3C7),
            title: 'Tulis Ulasan',
            subtitle:
                'Review produk dengan foto dapat bonus 5 poin per review approved.',
          ),
          const SizedBox(height: 10),
          const _InfoCard(
            icon: Icons.cake_outlined,
            iconColor: Color(0xFFEC4899),
            iconBg: Color(0xFFFCE7F3),
            title: 'Hadiah Ultah',
            subtitle:
                'Voucher khusus dikirim H-1 ulang tahun (lengkapi profil + birthDate).',
          ),
          const SizedBox(height: 20),
          // CTA tukar poin
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(
              context,
              '/member/loyalty/history',
            ),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Tukar Poin Jadi Voucher'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE8F8)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: NataloColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
