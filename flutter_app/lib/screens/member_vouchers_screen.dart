import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = Color(0xFF0B7FEA);

class MemberVouchersScreen extends StatefulWidget {
  const MemberVouchersScreen({super.key});

  @override
  State<MemberVouchersScreen> createState() => _MemberVouchersScreenState();
}

class _MemberVouchersScreenState extends State<MemberVouchersScreen> {
  late Future<List<MemberVoucher>> _vouchersFuture;

  @override
  void initState() {
    super.initState();
    _vouchersFuture = _loadVouchers();
  }

  Future<List<MemberVoucher>> _loadVouchers() async {
    if (!memberStore.isLoggedIn) return [];
    try {
      final vouchers = await memberService.fetchVouchers();
      return vouchers;
    } catch (_) {
      return [];
    }
  }

  Future<void> _refresh() async {
    setState(() => _vouchersFuture = _loadVouchers());
    await _vouchersFuture;
  }

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) {
      return const _LoginRequiredScaffold(title: 'Voucher Member');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Voucher Member')),
      body: FutureBuilder<List<MemberVoucher>>(
        future: _vouchersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppSkeletonList(itemCount: 4);
          }
          final vouchers = snapshot.data ?? [];
          // Empty state — match Capacitor pattern: illustration center + title
          // + subtitle + CTA tukar poin. RefreshIndicator tetap aktif supaya
          // user bisa pull-down refresh.
          if (vouchers.isEmpty) {
            return NataloPawRefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: const [
                  SizedBox(height: 80),
                  _VoucherEmptyState(),
                ],
              ),
            );
          }
          // Split jadi 2 section: bisa dipakai sekarang (applicable=true)
          // vs belum bisa dipakai (publik admin yg user belum cukup belanja,
          // upcoming, dll). Match Final Lock Spec — voucher tampil sampai
          // benar-benar tidak bisa dipakai (expired, sudah pakai → hidden
          // di backend).
          final applicable = vouchers.where((v) => v.applicable).toList();
          final unavailable = vouchers.where((v) => !v.applicable).toList();
          final children = <Widget>[
            _VoucherHeader(total: applicable.length),
            ...applicable
                .asMap()
                .entries
                .map((e) => _VoucherCard(voucher: e.value, index: e.key)),
            if (unavailable.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _SectionDivider(label: 'Belum bisa dipakai'),
              ...unavailable
                  .asMap()
                  .entries
                  .map((e) => _VoucherCard(voucher: e.value, index: e.key)),
            ],
          ];
          return NataloPawRefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => children[index],
            ),
          );
        },
      ),
    );
  }
}

/// Empty state Voucher Member — match Capacitor pattern: illustration besar
/// (icon ticket dalam light-blue circle), title bold, subtitle gray, CTA primary
/// "Tukar Poin Sekarang".
class _VoucherEmptyState extends StatelessWidget {
  const _VoucherEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                    : const Color(0xFFEAF5FF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _brandBlue.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_offer_outlined,
                color: _brandBlue,
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada voucher',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tukar poin loyalty kamu jadi voucher belanja, atau pantau '
              'halaman promo untuk dapat voucher gratis.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/member/loyalty'),
                icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                label: const Text(
                  'Tukar Poin Sekarang',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginRequiredScaffold extends StatelessWidget {
  final String title;

  const _LoginRequiredScaffold({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 76,
                width: 76,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                      : const Color(0xFFEAF5FF),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: _brandBlue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Login member diperlukan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk untuk melihat voucher yang aktif di akun kamu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/member/login'),
                child: const Text('Masuk Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherHeader extends StatelessWidget {
  final int total;

  const _VoucherHeader({required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
            : const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.local_offer_rounded, color: _brandBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total > 0
                      ? '$total voucher siap dipakai'
                      : 'Belum ada voucher siap dipakai',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total > 0
                      ? 'Tap "Pakai" untuk salin kode, lalu tempel saat checkout.'
                      : 'Voucher yang belum cukup belanja masih bisa kamu lihat di bawah.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
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

class _VoucherCard extends StatelessWidget {
  final MemberVoucher voucher;
  final int index;

  const _VoucherCard({required this.voucher, required this.index});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Opacity(
        // Voucher unavailable di-dim sedikit supaya user paham status-nya
        // beda dari yang ready dipakai. Tetap visible (per spec — tampil
        // sampai voucher tidak bisa dipakai sama sekali → hidden di backend).
        opacity: voucher.applicable ? 1.0 : 0.65,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: voucher.applicable
                ? cs.surface
                : (Theme.of(context).brightness == Brightness.dark
                    ? cs.surfaceContainerHighest
                    : const Color(0xFFFAFAFA)),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: voucher.applicable
                  ? const Color(0xFFBFDBFE)
                  : cs.outlineVariant,
            ),
            boxShadow: voucher.applicable
                ? [
                    BoxShadow(
                      color:
                          const Color(0xFF1E5FBF).withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                          : const Color(0xFFEAF5FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.confirmation_number_outlined,
                        color: _brandBlue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (voucher.isBrandExclusive) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF0DC),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFFCD9A0),
                              ),
                            ),
                            child: const Text(
                              'BRAND EKSKLUSIF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFFB85C00),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          voucher.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _brandBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          voucher.title,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${voucher.description} Berlaku sampai ${_formatDate(voucher.expiresAt)}.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tombol Pakai: disabled kalau voucher belum bisa dipakai
                  // (mis. belum cukup belanja, belum mulai, dst). Tetap show
                  // supaya user paham aksinya — cuma di-grey-out.
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: voucher.applicable
                          ? () async {
                              AppHaptics.success();
                              await Clipboard.setData(
                                ClipboardData(text: voucher.code),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Kode "${voucher.code}" disalin. Tempel saat checkout.',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  action: SnackBarAction(
                                    label: 'Ke Keranjang',
                                    onPressed: () => Navigator.pushNamed(
                                        context, '/cart'),
                                  ),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: cs.surfaceContainerHighest,
                        disabledForegroundColor: cs.onSurfaceVariant,
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: const Text('Pakai'),
                    ),
                  ),
                ],
              ),
              // Disabled reason banner — hanya muncul kalau voucher belum
              // bisa dipakai. Kasih tau user kenapa (mis. "Belum memenuhi
              // minimum belanja" / "Voucher belum berlaku").
              if (!voucher.applicable && voucher.disabledReason != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFB45309),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          voucher.disabledReason!,
                          style: const TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      }),
    );
  }
}

/// Divider antar section di list voucher — pisahin "bisa dipakai" dari
/// "belum bisa dipakai". Simple horizontal line + label muted.
class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: cs.outlineVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: cs.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
