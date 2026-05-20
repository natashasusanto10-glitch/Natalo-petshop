import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/admin_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  // Placeholder data sampai endpoint /api/admin/stats dibangun.
  int _ordersToday = 0;
  int _omzetToday = 0;
  int _pendingShip = 0;
  int _lowStockCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Endpoint sementara: /api/admin/dashboard-stats (TODO backend build).
      // Kalau 404, fall back ke placeholder 0 — supaya app tetap launchable
      // sebelum backend ready.
      try {
        final data = await adminApi.getJson('/api/admin/dashboard-stats');
        if (data is Map<String, dynamic>) {
          _ordersToday = (data['ordersToday'] as num?)?.toInt() ?? 0;
          _omzetToday = (data['omzetToday'] as num?)?.toInt() ?? 0;
          _pendingShip = (data['pendingShipment'] as num?)?.toInt() ?? 0;
          _lowStockCount = (data['lowStockCount'] as num?)?.toInt() ?? 0;
        }
      } on AdminApiException catch (e) {
        if (e.isNotFound) {
          // Backend belum ada endpoint — show zeros + soft notice.
          _error = 'Backend dashboard-stats belum tersedia. '
              'Build /api/admin/dashboard-stats di Next.js.';
        } else {
          rethrow;
        }
      }
    } on AdminApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Tidak bisa load data. Cek koneksi.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadStats,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: AdminColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Greeting
            const Text(
              'Halo, Admin 👋',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ringkasan toko hari ini',
              style: TextStyle(
                fontSize: 14,
                color: AdminColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AdminColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AdminColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Stat cards 2x2 grid.
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _StatCard(
                  loading: _loading,
                  icon: Icons.receipt_long_rounded,
                  iconColor: AdminColors.primary,
                  iconBg: AdminColors.primaryLight,
                  label: 'Pesanan Hari Ini',
                  value: _ordersToday.toString(),
                ),
                _StatCard(
                  loading: _loading,
                  icon: Icons.attach_money_rounded,
                  iconColor: AdminColors.success,
                  iconBg: const Color(0xFFE6F7F4),
                  label: 'Omzet Hari Ini',
                  value: formatRupiah(_omzetToday),
                  small: true,
                ),
                _StatCard(
                  loading: _loading,
                  icon: Icons.local_shipping_outlined,
                  iconColor: AdminColors.info,
                  iconBg: const Color(0xFFE3F2FD),
                  label: 'Perlu Dikirim',
                  value: _pendingShip.toString(),
                ),
                _StatCard(
                  loading: _loading,
                  icon: Icons.warning_amber_rounded,
                  iconColor: AdminColors.warning,
                  iconBg: const Color(0xFFFFF8E1),
                  label: 'Stok Kritis',
                  value: _lowStockCount.toString(),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Text(
              'Aksi Cepat',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _QuickActionTile(
              icon: Icons.add_box_outlined,
              label: 'Tambah Produk Baru',
              subtitle: 'Daftar produk + foto + varian',
              onTap: () {
                // TODO: navigate to add product screen
                _showComingSoon(context);
              },
            ),
            _QuickActionTile(
              icon: Icons.campaign_outlined,
              label: 'Broadcast Notifikasi',
              subtitle: 'Push notif ke semua customer',
              onTap: () => _showComingSoon(context),
            ),
            _QuickActionTile(
              icon: Icons.local_offer_outlined,
              label: 'Kelola Voucher',
              subtitle: 'Tambah promo & diskon baru',
              onTap: () => _showComingSoon(context),
            ),
            _QuickActionTile(
              icon: Icons.feed_outlined,
              label: 'Post Feed',
              subtitle: 'Upload video/foto promosi',
              onTap: () => _showComingSoon(context),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon — fitur ini dalam pengembangan.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final bool loading;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final bool small;

  const _StatCard({
    required this.loading,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const Spacer(),
          if (loading)
            Container(
              width: 60,
              height: 18,
              decoration: BoxDecoration(
                color: AdminColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: small ? 15 : 20,
                fontWeight: FontWeight.w800,
                color: AdminColors.textPrimary,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AdminColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.divider),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AdminColors.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: AdminColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AdminColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AdminColors.textSecondary,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AdminColors.textMuted,
        ),
      ),
    );
  }
}
