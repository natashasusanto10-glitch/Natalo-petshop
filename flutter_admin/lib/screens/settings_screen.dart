import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/fcm_service.dart';
import '../theme/admin_theme.dart';
import '../services/notification_counts.dart';
import 'abuse_flags_screen.dart';
import 'audit_log_screen.dart';
import 'broadcast_screen.dart';
import 'feed_create_screen.dart';
import 'feed_moderation_screen.dart';
import 'login_screen.dart';
import 'vouchers_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _onLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Keluar dari admin?'),
        content: const Text('Kamu perlu login ulang untuk akses lagi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AdminColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FcmService.instance.unregister();
    await adminApi.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: RefreshIndicator(
        color: AdminColors.primary,
        onRefresh: () => NotificationCounts.instance.refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
          // Header.
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AdminColors.primaryLight,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AdminColors.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Natalo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Logged in via admin session',
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _SectionHeader(label: 'Manajemen'),
          _SettingsTile(
            icon: Icons.feed_outlined,
            label: 'Post Feed Baru',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeedCreateScreen()),
            ),
          ),
          _SettingsTile(
            icon: Icons.rule_outlined,
            label: 'Moderasi Feed',
            subtitle: 'Review post komunitas customer',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FeedModerationScreen(),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.campaign_outlined,
            label: 'Broadcast Notifikasi',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BroadcastScreen()),
            ),
          ),
          _SettingsTile(
            icon: Icons.local_offer_outlined,
            label: 'Voucher & Promo',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VouchersScreen()),
            ),
          ),
          _SettingsTile(
            icon: Icons.category_outlined,
            label: 'Kategori & Brand',
            onTap: () => _comingSoon(context),
          ),
          _SettingsTile(
            icon: Icons.reviews_outlined,
            label: 'Moderasi Ulasan',
            onTap: () => _comingSoon(context),
          ),

          const SizedBox(height: 12),
          _SectionHeader(label: 'Trust & Safety'),
          _SettingsTile(
            icon: Icons.shield_outlined,
            label: 'Abuse Flags',
            subtitle: 'Review akun suspicious + voucher abuse',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AbuseFlagsScreen()),
            ),
          ),
          _SettingsTile(
            icon: Icons.fact_check_outlined,
            label: 'Audit Log',
            subtitle: 'Jejak aksi admin (read-only)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuditLogScreen()),
            ),
          ),

          const SizedBox(height: 12),
          _SectionHeader(label: 'Lainnya'),
          _SettingsTile(
            icon: Icons.web_outlined,
            label: 'Buka Dashboard Web',
            subtitle: 'natalopetshop.com/admin',
            onTap: () async {
              final uri = Uri.parse('https://www.natalopetshop.com/admin');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            label: 'Tentang Aplikasi',
            subtitle: 'Natalo Admin v1.0.2',
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Natalo Admin',
                applicationVersion: '1.0.2',
                applicationIcon: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AdminColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                  ),
                ),
                children: const [
                  SizedBox(height: 8),
                  Text(
                    'Admin/Seller app untuk Natalo Petshop. '
                    'Mobile-friendly companion untuk admin dashboard web.',
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Keluar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.danger,
                side: const BorderSide(color: AdminColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () => _onLogout(context),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      ),
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon — fitur ini dalam pengembangan.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AdminColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: AdminColors.textPrimary, size: 22),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AdminColors.textPrimary,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminColors.textMuted,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AdminColors.textMuted,
        ),
        onTap: onTap,
      ),
    );
  }
}
