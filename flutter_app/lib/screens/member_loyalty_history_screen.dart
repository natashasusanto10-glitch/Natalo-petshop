import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Riwayat poin loyalty — earnings + redemptions log.
class MemberLoyaltyHistoryScreen extends StatelessWidget {
  const MemberLoyaltyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Riwayat Poin'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 44,
                  color: NataloColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Belum ada riwayat poin',
                style: TextStyle(
                  color: NataloColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Earnings dan redemptions poin akan muncul di sini.\nMulai belanja untuk dapat poin pertama.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/products'),
                child: const Text('Jelajahi Produk'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
