import 'package:flutter/material.dart';

import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/animated_counter.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Tier penukaran poin → voucher. Match PWA `app/api/member/claim-voucher/route.ts`
/// TIERS constant. Server adalah source of truth — kalau berubah di backend,
/// update di sini juga. Untuk Phase 2 bisa fetch via GET endpoint.
const _redeemTiers = <_LoyaltyTier>[
  _LoyaltyTier(points: 50, discountAmount: 5000),
  _LoyaltyTier(points: 100, discountAmount: 10000),
  _LoyaltyTier(points: 200, discountAmount: 20000),
];

class _LoyaltyTier {
  final int points;
  final int discountAmount;
  const _LoyaltyTier({required this.points, required this.discountAmount});
}

/// Screen tukar poin loyalty jadi voucher. Match PWA
/// `app/account/loyalty/redeem/RedeemPointsClient.tsx`:
/// - Balance card biru di atas (Saldo Poin Kamu)
/// - 3 tier voucher (Rp5k/10k/20k) dengan tombol Tukar / disabled state
/// - Confirmation dialog sebelum eksekusi
/// - Section "Cara kerja penukaran"
class MemberLoyaltyScreen extends StatefulWidget {
  const MemberLoyaltyScreen({super.key});

  @override
  State<MemberLoyaltyScreen> createState() => _MemberLoyaltyScreenState();
}

class _MemberLoyaltyScreenState extends State<MemberLoyaltyScreen> {
  int _claimingTierPoints = -1;

  int get _availablePoints => memberStore.profile?.points ?? 0;

  Future<void> _confirmAndClaim(_LoyaltyTier tier) async {
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: _brandBlue,
              size: 28,
            ),
          ),
          title: const Text(
            'Tukar poin menjadi voucher?',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Voucher ${formatRupiah(tier.discountAmount.toDouble())} akan ditukar '
                'dengan ${tier.points} poin.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Poin akan dipotong setelah kamu konfirmasi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ya, Tukar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _executeClaim(tier);
  }

  Future<void> _executeClaim(_LoyaltyTier tier) async {
    setState(() => _claimingTierPoints = tier.points);
    try {
      final result = await memberService.claimLoyaltyVoucher(tier.points);
      if (!mounted) return;
      // Optimistic update — kurangi balance lokal. Idealnya re-fetch profile
      // dari server, tapi update lokal cukup untuk visual feedback instan.
      final profile = memberStore.profile;
      if (profile != null) {
        memberStore.setProfile(
          profile.copyWith(points: profile.points - tier.points),
        );
      }
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voucher ${result.code} berhasil ditukar! Cek di Voucher Member.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => Navigator.pushNamed(context, '/member/vouchers'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menukar poin: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _claimingTierPoints = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Tukar Poin')),
      body: AnimatedBuilder(
        animation: memberStore,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _BalanceCard(points: _availablePoints),
              const SizedBox(height: 14),
              // Progress bar visual ke next tier — animated, kasih
              // user motivasi belanja lagi untuk dapat reward lebih
              // besar. Pure client-side calculation dari _redeemTiers.
              _TierProgressCard(points: _availablePoints),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Pilih Voucher',
                  style: TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final tier in _redeemTiers) ...[
                _TierCard(
                  tier: tier,
                  availablePoints: _availablePoints,
                  loading: _claimingTierPoints == tier.points,
                  onClaim: () => _confirmAndClaim(tier),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              const _HowItWorksCard(),
            ],
          );
        },
      ),
    );
  }
}

/// Animated progress bar ke next tier voucher. Kasih user visual cue
/// "tinggal X poin lagi untuk dapat Rp10k". Drive belanja lagi.
class _TierProgressCard extends StatefulWidget {
  final int points;

  const _TierProgressCard({required this.points});

  @override
  State<_TierProgressCard> createState() => _TierProgressCardState();
}

class _TierProgressCardState extends State<_TierProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void didUpdateWidget(_TierProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({int? next, double progress, String label}) _calc() {
    final points = widget.points;
    const tiers = _redeemTiers;
    // Find next tier yang user belum mampu claim.
    for (var i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      if (points < tier.points) {
        final prevThreshold = i == 0 ? 0 : tiers[i - 1].points;
        final range = tier.points - prevThreshold;
        final progress =
            range == 0 ? 1.0 : ((points - prevThreshold) / range).clamp(0.0, 1.0);
        final lacking = tier.points - points;
        return (
          next: tier.points,
          progress: progress,
          label: '$lacking poin lagi untuk voucher '
              '${formatRupiah(tier.discountAmount.toDouble())}',
        );
      }
    }
    // Sudah lampaui tier tertinggi.
    return (
      next: null,
      progress: 1.0,
      label: 'Tier maksimal tercapai! Tukar voucher kapan saja.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _calc();
    return GlassSurface(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFEAB308),
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                'Progress Tier',
                style: TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (info.next != null)
                Text(
                  '${widget.points} / ${info.next} poin',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: info.progress * _animation.value,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(_brandBlue),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            info.label,
            style: TextStyle(
              color: info.next == null
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int points;
  const _BalanceCard({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Align gradient ke NataloColors primary → primaryDark
        // (sebelumnya pakai Tailwind blue-500 → blue-700 yang sedikit drift).
        gradient: const LinearGradient(
          colors: [Color(0xFF0B7FEA), Color(0xFF075CB5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _brandBlue.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SALDO POIN KAMU',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          // Animated ticker — saat user redeem poin, angka berubah dengan
          // tween halus instead of jump.
          AnimatedCounter(
            value: points,
            formatter: (v) => '${_formatThousands(v.round())} poin',
            duration: const Duration(milliseconds: 800),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tukar poin jadi voucher belanja. Voucher akan masuk ke Voucher Member.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final _LoyaltyTier tier;
  final int availablePoints;
  final bool loading;
  final VoidCallback onClaim;

  const _TierCard({
    required this.tier,
    required this.availablePoints,
    required this.loading,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final canClaim = availablePoints >= tier.points;

    return GlassSurface(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              // Align ke NataloColors.primaryLight (sebelumnya 0xFFEEF5FF
              // sedikit beda dari 0xFFEAF5FF).
              color: const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(14),
            ),
            // Icon color align ke _brandBlue (sebelumnya 0xFF1677FF).
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: _brandBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voucher ${formatRupiah(tier.discountAmount.toDouble())}',
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Butuh ${tier.points} poin',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: AppPressable(
              onTap: (canClaim && !loading) ? onClaim : null,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: canClaim
                      ? _brandBlue
                      : const Color(0xFFEFF2F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: loading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        canClaim ? 'Tukar' : 'Poin belum cukup',
                        style: TextStyle(
                          color: canClaim
                              ? Colors.white
                              : const Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      'Poin akan dipotong setelah konfirmasi',
      'Voucher masuk ke Voucher Member',
      'Voucher dapat dipakai saat checkout',
    ];
    return GlassSurface(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cara kerja penukaran',
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF16A34A),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
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

String _formatThousands(int n) {
  final s = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final reverseIndex = s.length - i;
    buffer.write(s[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}
