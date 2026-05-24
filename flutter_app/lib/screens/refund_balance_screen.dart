import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _textDark = Color(0xFF111111);
const _textMuted = Color(0xFF6B7280);
const _success = Color(0xFF059669);
const _danger = Color(0xFFEF4444);

/// Saldo Refund — halaman aktif user untuk lihat saldo + history.
///
/// Sumber data: GET /api/member/refund-balance
///
/// Layout:
///  - Balance card (Rupiah value + label + CTA "Belanja Sekarang")
///  - Riwayat saldo (ledger entries, latest 50)
///  - Empty state kalau saldo=0 + no history
///
/// Behavior:
///  - Pull-to-refresh — refetch dari backend
///  - Tap entry → (V2) navigate ke order detail kalau ada sourceOrderId
class RefundBalanceScreen extends StatefulWidget {
  const RefundBalanceScreen({super.key});

  @override
  State<RefundBalanceScreen> createState() => _RefundBalanceScreenState();
}

class _RefundBalanceScreenState extends State<RefundBalanceScreen> {
  late Future<_RefundBalanceData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RefundBalanceData> _load() async {
    if (!memberStore.isLoggedIn) {
      return const _RefundBalanceData(balance: 0, history: []);
    }
    try {
      final data = await apiClient.getJson('/api/member/refund-balance');
      if (data is! Map<String, dynamic>) return const _RefundBalanceData.empty();
      final wallet = data['wallet'];
      final history = data['history'];
      final balance = wallet is Map
          ? (wallet['availableBalance'] as num?)?.toInt() ?? 0
          : 0;
      final entries = <_LedgerEntry>[];
      if (history is List) {
        for (final raw in history) {
          if (raw is Map<String, dynamic>) {
            entries.add(_LedgerEntry.fromJson(raw));
          }
        }
      }
      return _RefundBalanceData(balance: balance, history: entries);
    } catch (_) {
      return const _RefundBalanceData.empty();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saldo Refund')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Login dulu untuk lihat saldo refund.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textMuted),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Saldo Refund')),
      body: FutureBuilder<_RefundBalanceData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppSkeletonList(itemCount: 5);
          }
          final data = snapshot.data ?? const _RefundBalanceData.empty();
          return NataloPawRefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _BalanceCard(balance: data.balance),
                const SizedBox(height: 20),
                if (data.history.isEmpty)
                  const _EmptyHistory()
                else ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'Riwayat Saldo',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ...data.history.map(_LedgerCard.new),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E5FBF), Color(0xFF0B7FEA)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E5FBF).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Saldo tersedia',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.90),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatRupiah(balance.toDouble()),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            balance > 0
                ? 'Bisa dipakai saat checkout pesanan berikutnya'
                : 'Belum ada saldo refund',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (balance > 0) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _brandBlue,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Belanja Sekarang',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5FF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: _brandBlue,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada riwayat saldo',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Saldo refund akan muncul di sini jika ada pengembalian dana dari pesanan kamu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerCard extends StatelessWidget {
  final _LedgerEntry entry;

  const _LedgerCard(this.entry);

  /// Tap behavior:
  ///   - CREDIT / REVERSAL (refund masuk / dikembalikan) — navigate ke
  ///     RefundDetailScreen via sourceRefundCaseId (kalau ada).
  ///   - DEBIT (saldo dipakai di checkout) — navigate ke order detail.
  ///     Untuk MVP, snackbar arahkan user ke Tab Transaksi (existing
  ///     route /member/order-detail butuh OrderSummary object).
  ///   - Entry tanpa sourceId — disable tap (visual hint: no chevron).
  void _onTap(BuildContext context) {
    final isCredit = entry.type == 'CREDIT' || entry.type == 'REVERSAL';
    if (isCredit && entry.sourceRefundCaseId != null) {
      Navigator.pushNamed(
        context,
        '/member/refund-detail',
        arguments: entry.sourceRefundCaseId,
      );
      return;
    }
    if (!isCredit && entry.sourceOrderId != null) {
      // DEBIT entry — arahkan ke detail order. Future improvement:
      // route accept orderId, fetch order on-the-fly.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Buka Tab Transaksi → cari pesanan terkait di list "Pesanan Saya".',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.type == 'CREDIT' || entry.type == 'REVERSAL';
    final sign = isCredit ? '+' : '-';
    final amountColor = isCredit ? _success : _danger;
    final iconBg = isCredit
        ? const Color(0xFFD1FAE5)
        : const Color(0xFFFEE2E2);
    final iconColor = isCredit ? _success : _danger;
    // Determine if entry is clickable — credit dengan refundCaseId atau
    // debit dengan orderId.
    final clickable = (isCredit && entry.sourceRefundCaseId != null) ||
        (!isCredit && entry.sourceOrderId != null);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: clickable ? () => _onTap(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '$sign${formatRupiah(entry.amount.toDouble())}',
                      style: TextStyle(
                        color: amountColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (entry.note != null && entry.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.note!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  entry.formattedDate,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (clickable) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF98A2B3),
              size: 18,
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }
}

class _LedgerEntry {
  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final String? sourceOrderId;
  final String? sourceRefundCaseId;
  final String? note;
  final DateTime createdAt;

  const _LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.sourceOrderId,
    this.sourceRefundCaseId,
    this.note,
  });

  factory _LedgerEntry.fromJson(Map<String, dynamic> json) {
    return _LedgerEntry(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'CREDIT').toString(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
      sourceOrderId: json['sourceOrderId']?.toString(),
      sourceRefundCaseId: json['sourceRefundCaseId']?.toString(),
      note: json['note']?.toString(),
      createdAt: DateTime.tryParse(
            (json['createdAt'] ?? '').toString(),
          )?.toLocal() ??
          DateTime.now(),
    );
  }

  String get title {
    switch (type) {
      case 'CREDIT':
        return 'Refund masuk';
      case 'DEBIT':
        return 'Dipakai untuk pesanan';
      case 'REVERSAL':
        return 'Saldo dikembalikan';
      case 'ADJUSTMENT':
        return 'Penyesuaian saldo';
      default:
        return 'Transaksi saldo';
    }
  }

  String get formattedDate {
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
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '${createdAt.day} ${months[createdAt.month - 1]} ${createdAt.year}, $hour:$minute';
  }
}

class _RefundBalanceData {
  final int balance;
  final List<_LedgerEntry> history;

  const _RefundBalanceData({required this.balance, required this.history});

  const _RefundBalanceData.empty()
      : balance = 0,
        history = const [];
}
