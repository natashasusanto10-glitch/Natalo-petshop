import 'package:flutter/material.dart';

import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _primaryDark = Color(0xFF075CB5);
const _primaryLight = Color(0xFFEAF5FF);
const _success = Color(0xFF16A34A);
const _danger = Color(0xFFEF4444);

/// **Riwayat Poin** — list transaksi earn/redeem loyalty point member.
///
/// Layout match Capacitor pattern:
/// - Gradient header dengan saldo poin current
/// - List transaksi (icon +/- + description + delta + date)
/// - Empty state kalau belum ada transaksi
class MemberLoyaltyHistoryScreen extends StatefulWidget {
  const MemberLoyaltyHistoryScreen({super.key});

  @override
  State<MemberLoyaltyHistoryScreen> createState() =>
      _MemberLoyaltyHistoryScreenState();
}

class _MemberLoyaltyHistoryScreenState
    extends State<MemberLoyaltyHistoryScreen> {
  late Future<List<LoyaltyHistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = memberService.fetchLoyaltyHistory();
  }

  Future<void> _refresh() async {
    setState(() {
      _historyFuture = memberService.fetchLoyaltyHistory();
    });
    await _historyFuture;
  }

  @override
  Widget build(BuildContext context) {
    final points = memberStore.profile?.points ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Poin')),
      body: NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<LoyaltyHistoryEntry>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _LoyaltyHeaderCard(points: points),
                  const SizedBox(height: 16),
                  const AppSkeletonList(itemCount: 4),
                ],
              );
            }
            final entries = snapshot.data ?? const [];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _LoyaltyHeaderCard(points: points),
                const SizedBox(height: 16),
                if (entries.isEmpty) ...[
                  const SizedBox(height: 60),
                  const _LoyaltyHistoryEmpty(),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10, left: 4),
                    child: Text(
                      'Transaksi Poin',
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  for (var i = 0; i < entries.length; i++) ...[
                    _LoyaltyHistoryEntryCard(entry: entries[i], index: i),
                    if (i < entries.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Gradient blue header dengan saldo poin saat ini — visual focus utama.
class _LoyaltyHeaderCard extends StatelessWidget {
  final int points;

  const _LoyaltyHeaderCard({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandBlue, _primaryDark],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _brandBlue.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Saldo poin kamu',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$points poin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
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

/// Card per-transaksi: icon arrow up/down dengan warna + description + delta + date.
class _LoyaltyHistoryEntryCard extends StatelessWidget {
  final LoyaltyHistoryEntry entry;
  final int index;

  const _LoyaltyHistoryEntryCard({
    required this.entry,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isEarn = entry.isEarn;
    final color = isEarn ? _success : _danger;
    final subtitle = entry.isReviewBonus
        ? 'Terima kasih sudah memberi ulasan'
        : formatRelativeTime(entry.createdAt);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isEarn
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isEarn ? '+' : ''}${entry.delta}',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state — belum ada transaksi poin.
class _LoyaltyHistoryEmpty extends StatelessWidget {
  const _LoyaltyHistoryEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: _primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                color: _brandBlue,
                size: 52,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Belum ada transaksi poin',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF111111),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Mulai belanja untuk dapat poin loyalty. Setiap pembelian akan tercatat di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
