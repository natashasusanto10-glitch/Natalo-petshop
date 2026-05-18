import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Member Vouchers — daftar voucher yang user sudah claim atau available.
/// Saat ini empty state — future: integrate dengan voucher service untuk
/// fetch list voucher member.
class MemberVouchersScreen extends StatelessWidget {
  const MemberVouchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          title: const Text('Voucher Saya'),
          backgroundColor: const Color(0xFFF7FAFF),
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tersedia'),
              Tab(text: 'Sudah Dipakai'),
            ],
            labelColor: NataloColors.primary,
            unselectedLabelColor: NataloColors.textSecondary,
            indicatorColor: NataloColors.primary,
          ),
        ),
        body: TabBarView(
          children: [
            _EmptyVoucherState(
              title: 'Belum ada voucher tersedia',
              subtitle:
                  'Cek halaman home atau tukar poin untuk dapat voucher diskon dan gratis ongkir.',
              ctaLabel: 'Tukar Poin',
              onAction: () =>
                  Navigator.pushReplacementNamed(context, '/member/loyalty'),
            ),
            const _EmptyVoucherStateStatic(
              title: 'Belum ada riwayat',
              subtitle:
                  'Voucher yang sudah dipakai akan muncul di sini setelah checkout selesai.',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVoucherState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onAction;

  const _EmptyVoucherState({
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onAction,
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
                color: const Color(0xFFFCE7F3),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.local_offer_outlined,
                size: 44,
                color: Color(0xFFBE185D),
              ),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              child: Text(ctaLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVoucherStateStatic extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyVoucherStateStatic({
    required this.title,
    required this.subtitle,
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
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 44,
                color: NataloColors.textTertiary,
              ),
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
          ],
        ),
      ),
    );
  }
}
