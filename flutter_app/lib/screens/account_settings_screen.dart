import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';
import '../services/biometric_service.dart';
import '../services/push_notification_service.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../state/settings_store.dart';
import '../utils/app_review.dart';
import '../utils/haptics.dart';
import '../utils/in_app_browser.dart';
import '../widgets/app_toast.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _pageBg = Color(0xFFF8FAFC);
const _dangerRed = Color(0xFFEF4444);

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: const Text(
          'Pengaturan',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
      ),
      body: const _SettingsContent(),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        SettingsSection(
          title: 'AKUN',
          children: [
            SettingsListItem(
              icon: Icons.person_outline_rounded,
              title: 'Ubah Profil',
              subtitle: 'Atur identitas dan foto profil kamu',
              onTap: () => Navigator.pushNamed(context, '/member/profile'),
            ),
            SettingsListItem(
              icon: Icons.location_on_outlined,
              title: 'Daftar Alamat',
              subtitle: 'Kelola alamat pengiriman',
              onTap: () => Navigator.pushNamed(context, '/member/addresses'),
            ),
            SettingsListItem(
              icon: Icons.shield_outlined,
              title: 'Keamanan Akun',
              subtitle: 'Ubah password, sesi aktif, hapus akun',
              onTap: () => Navigator.pushNamed(context, '/account/security'),
            ),
            SettingsListItem(
              icon: Icons.notifications_none_rounded,
              title: 'Notifikasi',
              subtitle: 'Atur preferensi notifikasi aplikasi',
              onTap: () =>
                  Navigator.pushNamed(context, '/settings/notifications'),
            ),
            SettingsListItem(
              icon: Icons.privacy_tip_outlined,
              title: 'Privasi Akun',
              subtitle: 'Pengaturan data dan privasi akun',
              onTap: () => AppInAppBrowser.openKebijakanPrivasi(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsSection(
          title: 'PENGATURAN APLIKASI',
          collapsible: true,
          children: [
            AnimatedBuilder(
              animation: appSettingsStore,
              builder: (context, _) {
                return SettingsListItem(
                  icon: _themeIcon(appSettingsStore.themeMode),
                  title: 'Mode Tampilan',
                  subtitle: 'Terang, gelap, atau ikuti sistem',
                  trailing: Text(
                    _themeLabel(appSettingsStore.themeMode),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => _openThemeSheet(context),
                );
              },
            ),
            AnimatedBuilder(
              animation: appSettingsStore,
              builder: (context, _) {
                return SettingsToggleItem(
                  icon: Icons.smart_display_outlined,
                  title: 'Putar Otomatis Video',
                  subtitle: 'Putar video Feed secara otomatis',
                  value: appSettingsStore.feedAutoplay,
                  onChanged: appSettingsStore.setFeedAutoplay,
                );
              },
            ),
            AnimatedBuilder(
              animation: appSettingsStore,
              builder: (context, _) {
                return SettingsValueItem(
                  icon: Icons.high_quality_outlined,
                  title: 'Kualitas Video Feed',
                  subtitle: 'Atur kualitas video yang diputar',
                  valueText: appSettingsStore.feedVideoQualityLabel,
                  onTap: () => _openVideoQualitySheet(context),
                );
              },
            ),
            SettingsValueItem(
              icon: Icons.cleaning_services_rounded,
              title: 'Bersihkan Cache',
              subtitle: 'Hapus cache gambar dan video sementara',
              valueText: 'Hapus',
              onTap: () => _confirmClearCache(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsSection(
          title: 'SEPUTAR NATALO',
          collapsible: true,
          children: [
            SettingsListItem(
              icon: Icons.pets_rounded,
              title: 'Tentang Natalo',
              subtitle: 'Kenali Natalo Petshop',
              onTap: () => AppInAppBrowser.openTentangNatalo(context),
            ),
            SettingsListItem(
              icon: Icons.help_outline_rounded,
              title: 'Pusat Bantuan',
              subtitle: 'FAQ, cara order, dan kontak toko',
              onTap: () => AppInAppBrowser.openBantuan(context),
            ),
            SettingsListItem(
              icon: Icons.checklist_rounded,
              title: 'Cara Pemesanan',
              subtitle: 'Panduan order step-by-step',
              onTap: () => AppInAppBrowser.openCaraPemesanan(context),
            ),
            SettingsListItem(
              icon: Icons.description_outlined,
              title: 'Syarat & Ketentuan',
              subtitle: 'Ketentuan penggunaan layanan',
              onTap: () => AppInAppBrowser.open(
                context,
                url: '/syarat-ketentuan',
                title: 'Syarat & Ketentuan',
              ),
            ),
            SettingsListItem(
              icon: Icons.privacy_tip_outlined,
              title: 'Kebijakan Privasi',
              subtitle: 'Cara kami menjaga data kamu',
              onTap: () => AppInAppBrowser.openKebijakanPrivasi(context),
            ),
            SettingsListItem(
              icon: Icons.assignment_return_outlined,
              title: 'Kebijakan Pengembalian',
              subtitle: 'Syarat retur dan refund',
              onTap: () => AppInAppBrowser.openKebijakanPengembalian(context),
            ),
            SettingsListItem(
              icon: Icons.star_border_rounded,
              title: 'Ulas Aplikasi Ini',
              subtitle: 'Beri rating untuk Natalo',
              onTap: () async {
                await AppReview.maybeRequest();
                if (context.mounted) {
                  AppToast.show(
                    context,
                    'Terima kasih sudah mendukung Natalo.',
                    kind: ToastKind.success,
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 22),
        _LogoutSettingsCard(onTap: () => _confirmLogout(context)),
        const SizedBox(height: 26),
        const _AppVersionFooter(),
      ],
    );
  }

}

class SettingsSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool collapsible;
  final ValueChanged<bool>? onExpansionChanged;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.collapsible = false,
    this.onExpansionChanged,
  });

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.collapsible
              ? () {
                  setState(() => _expanded = !_expanded);
                  widget.onExpansionChanged?.call(_expanded);
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: _brandBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (widget.collapsible)
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(children: _withDividers(widget.children)),
                ),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> children) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          const Padding(
            padding: EdgeInsets.only(left: 72),
            child: Divider(height: 1, color: Color(0xFFEFF2F6)),
          ),
        );
      }
    }
    return result;
  }
}

class SettingsListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool isDanger;
  final Color? iconColor;
  final Color? iconBackgroundColor;

  const SettingsListItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.isDanger = false,
    this.iconColor,
    this.iconBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? _dangerRed : iconColor ?? _brandBlue;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: iconBackgroundColor ??
                    (isDanger
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFEAF5FF)),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDanger ? _dangerRed : const Color(0xFF17202A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ] else if (showChevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsToggleItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggleItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsListItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      showChevron: false,
      trailing: Switch.adaptive(
        value: value,
        activeThumbColor: _brandBlue,
        onChanged: onChanged,
      ),
    );
  }
}

class SettingsValueItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String valueText;
  final VoidCallback? onTap;

  const SettingsValueItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsListItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            valueText,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
      showChevron: false,
    );
  }
}

class _LogoutSettingsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _LogoutSettingsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: SettingsListItem(
        icon: Icons.logout_rounded,
        title: 'Keluar Akun',
        subtitle: 'Akhiri sesi akun di perangkat ini',
        isDanger: true,
        onTap: onTap,
      ),
    );
  }
}

class _AppVersionFooter extends StatefulWidget {
  const _AppVersionFooter();

  @override
  State<_AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<_AppVersionFooter> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = 'Versi ${info.version}');
    } catch (_) {
      if (mounted) setState(() => _version = 'Versi 1.0.0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF5FF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pets_rounded, color: _brandBlue, size: 18),
        ),
        const SizedBox(height: 8),
        Text(
          _version.isEmpty ? 'Memuat versi...' : _version,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

IconData _themeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      return Icons.dark_mode_outlined;
    case ThemeMode.system:
      return Icons.brightness_auto_outlined;
    case ThemeMode.light:
      return Icons.light_mode_outlined;
  }
}

String _themeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      return 'Gelap';
    case ThemeMode.system:
      return 'Sistem';
    case ThemeMode.light:
      return 'Terang';
  }
}

Future<void> _openThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: AnimatedBuilder(
            animation: appSettingsStore,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mode Tampilan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  _SheetOption(
                    icon: Icons.light_mode_rounded,
                    title: 'Terang',
                    selected: appSettingsStore.themeMode == ThemeMode.light,
                    onTap: () async {
                      await appSettingsStore.setThemeMode(ThemeMode.light);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  _SheetOption(
                    icon: Icons.dark_mode_rounded,
                    title: 'Gelap',
                    selected: appSettingsStore.themeMode == ThemeMode.dark,
                    onTap: () async {
                      await appSettingsStore.setThemeMode(ThemeMode.dark);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  _SheetOption(
                    icon: Icons.brightness_auto_rounded,
                    title: 'Ikuti Sistem',
                    selected: appSettingsStore.themeMode == ThemeMode.system,
                    onTap: () async {
                      await appSettingsStore.setThemeMode(ThemeMode.system);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

Future<void> _openVideoQualitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: AnimatedBuilder(
            animation: appSettingsStore,
            builder: (context, _) {
              final current = appSettingsStore.feedVideoQuality;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kualitas Video Feed',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  _SheetOption(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Otomatis',
                    selected: current == 'auto',
                    onTap: () async {
                      await appSettingsStore.setFeedVideoQuality('auto');
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  _SheetOption(
                    icon: Icons.data_saver_on_rounded,
                    title: 'Hemat Data',
                    selected: current == 'data_saver',
                    onTap: () async {
                      await appSettingsStore.setFeedVideoQuality('data_saver');
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  _SheetOption(
                    icon: Icons.high_quality_rounded,
                    title: 'Tinggi',
                    selected: current == 'high',
                    onTap: () async {
                      await appSettingsStore.setFeedVideoQuality('high');
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading:
          Icon(icon, color: selected ? _brandBlue : const Color(0xFF64748B)),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: _brandBlue)
          : null,
    );
  }
}

Future<void> _confirmClearCache(BuildContext context) async {
  AppHaptics.tap();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: const Icon(
        Icons.cleaning_services_rounded,
        color: _brandBlue,
        size: 36,
      ),
      title: const Text(
        'Bersihkan cache?',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: const Text(
        'Cache gambar dan video sementara akan dihapus. Data akun, pesanan, dan wishlist kamu tetap aman.',
        textAlign: TextAlign.center,
        style: TextStyle(height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: _brandBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Bersihkan'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  imageCache.clear();
  imageCache.clearLiveImages();
  await DefaultCacheManager().emptyCache();
  await CachedNetworkImage.evictFromCache('');
  if (!context.mounted) return;
  AppToast.show(
    context,
    'Cache berhasil dibersihkan',
    kind: ToastKind.success,
    icon: Icons.check_circle_rounded,
  );
}

Future<void> _confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: const Icon(Icons.logout_rounded, color: _dangerRed, size: 36),
      title: const Text(
        'Keluar dari akun?',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: const Text(
        'Kamu perlu masuk kembali untuk melihat pesanan, poin, voucher, wishlist, dan data akunmu.',
        textAlign: TextAlign.center,
        style: TextStyle(height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: _dangerRed),
          child: const Text('Keluar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  AppCrashlytics.log('User logout');
  AppCrashlytics.setUserId(null);
  AppAnalytics.setUserId(null);
  pushNotificationService.unregisterFromServer();
  await biometricService.disable();
  await memberStore.logout();
  favoriteStore.clear();
  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }
}
