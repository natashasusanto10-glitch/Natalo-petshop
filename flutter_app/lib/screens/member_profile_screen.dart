import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../state/favorite_store.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_avatar.dart';

/// Profile member — full premium dengan hero card, quick stats, edit
/// per field via bottom sheet, quick actions ke screen member lain,
/// logout button. Match struktur Android.
class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({super.key});

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  int _ordersCount = 0;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    favoriteStore.ensureLoaded();
  }

  Future<void> _loadStats() async {
    try {
      final orders = await memberService.fetchOrders();
      if (!mounted) return;
      setState(() {
        _ordersCount = orders.length;
        _loadingStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text(
          'Profil Saya',
          style: TextStyle(
            color: NataloColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0xFFF7FAFF),
        iconTheme: const IconThemeData(color: NataloColors.textPrimary),
      ),
      body: AnimatedBuilder(
        animation: memberStore,
        builder: (context, _) {
          final profile = memberStore.profile;
          if (profile == null) return const _NotLoggedInState();
          return RefreshIndicator(
            color: NataloColors.primary,
            onRefresh: () async {
              await _loadStats();
              await favoriteStore.refresh();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _HeroCard(profile: profile),
                const SizedBox(height: 14),
                _QuickStatsRow(
                  ordersCount: _ordersCount,
                  loadingStats: _loadingStats,
                ),
                const SizedBox(height: 18),
                const _SectionLabel('Data Pribadi'),
                const SizedBox(height: 8),
                _EditableTilesGroup(
                  profile: profile,
                  onUpdated: () {
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 18),
                const _SectionLabel('Aktivitas Saya'),
                const SizedBox(height: 8),
                _QuickActionsGrid(),
                const SizedBox(height: 18),
                const _SectionLabel('Akun & Keamanan'),
                const SizedBox(height: 8),
                _AccountSecurityGroup(),
                const SizedBox(height: 22),
                _LogoutButton(),
                const SizedBox(height: 8),
                _AppVersionFooter(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ────────────────────────── HERO CARD ──────────────────────────

class _HeroCard extends StatelessWidget {
  final MemberProfile profile;
  const _HeroCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.isNotEmpty
        ? profile.name[0].toUpperCase()
        : '?';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E5FBF),
            Color(0xFF3B82F6),
            Color(0xFF60A5FA),
          ],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: NataloColors.primary.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Glossy shine overlay top-left
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.35, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProfileAvatar(
                initial: initial,
                size: 72,
                fontSize: 26,
                showCameraBadge: true,
                onTap: () {
                  AppHaptics.tap();
                  AppToast.show(
                    ScaffoldMessenger.of(context).context,
                    'Upload foto profil belum tersedia — segera hadir.',
                    kind: ToastKind.info,
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isNotEmpty ? profile.name : 'Member Natalo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if ((profile.email ?? '').isNotEmpty)
                      Text(
                        profile.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    if ((profile.phone ?? '').isNotEmpty)
                      Text(
                        profile.phone!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30),
                          width: 0.6,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            profile.isAdmin ? 'Admin' : 'Member',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── QUICK STATS ──────────────────────────

class _QuickStatsRow extends StatelessWidget {
  final int ordersCount;
  final bool loadingStats;

  const _QuickStatsRow({
    required this.ordersCount,
    required this.loadingStats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8F8)),
      ),
      child: Row(
        children: [
          _StatCell(
            icon: Icons.receipt_long_rounded,
            iconColor: const Color(0xFF1E5FBF),
            value: loadingStats ? '—' : '$ordersCount',
            label: 'Pesanan',
            onTap: () => Navigator.pushNamed(context, '/member/orders'),
          ),
          _StatDivider(),
          AnimatedBuilder(
            animation: favoriteStore,
            builder: (context, _) => _StatCell(
              icon: Icons.favorite_rounded,
              iconColor: const Color(0xFFEF4444),
              value: '${favoriteStore.count}',
              label: 'Favorit',
              onTap: () => Navigator.pushNamed(context, '/wishlist'),
            ),
          ),
          _StatDivider(),
          _StatCell(
            icon: Icons.stars_rounded,
            iconColor: const Color(0xFFF59E0B),
            value: '—',
            label: 'Poin',
            onTap: () => Navigator.pushNamed(context, '/member/loyalty'),
          ),
          _StatDivider(),
          _StatCell(
            icon: Icons.confirmation_number_rounded,
            iconColor: const Color(0xFF16A34A),
            value: '—',
            label: 'Voucher',
            onTap: () => Navigator.pushNamed(context, '/member/vouchers'),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.7,
      height: 30,
      color: const Color(0xFFE5EAF3),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback onTap;

  const _StatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AppHaptics.tap();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: NataloColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: NataloColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────── SECTION LABEL ──────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: NataloColors.textPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 13.5,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ────────────────────────── EDITABLE FIELDS ──────────────────────────

class _EditableTilesGroup extends StatelessWidget {
  final MemberProfile profile;
  final VoidCallback onUpdated;
  const _EditableTilesGroup({
    required this.profile,
    required this.onUpdated,
  });

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required String hint,
    required String fieldKey,
    required String initial,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final newValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditFieldSheet(
        title: title,
        hint: hint,
        initial: initial,
        keyboardType: keyboardType,
      ),
    );
    if (newValue == null) return;
    final trimmed = newValue.trim();
    if (trimmed.isEmpty || trimmed == initial.trim()) return;
    await _saveField(context, fieldKey, trimmed);
  }

  Future<void> _editBirthDate(BuildContext context) async {
    final initial = profile.birthDate ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1925),
      lastDate: DateTime.now(),
      helpText: 'Tanggal lahir',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null) return;
    if (picked == profile.birthDate) return;
    await _saveField(context, 'birthDate', picked);
  }

  Future<void> _saveField(
    BuildContext context,
    String fieldKey,
    Object value,
  ) async {
    AppHaptics.tap();
    final updated = await memberService.updateProfile(
      name: fieldKey == 'name' ? value as String : null,
      email: fieldKey == 'email' ? value as String : null,
      phone: fieldKey == 'phone' ? value as String : null,
      birthDate: fieldKey == 'birthDate' ? value as DateTime : null,
    );
    if (!context.mounted) return;
    if (updated != null) {
      // Sync ke memberStore.
      await memberStore.setSession(profile: updated);
      AppHaptics.success();
      AppToast.show(
        context,
        'Profil tersimpan.',
        kind: ToastKind.success,
      );
      onUpdated();
    } else {
      AppToast.show(
        context,
        'Update belum berhasil — backend belum siap atau koneksi error.',
        kind: ToastKind.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8F8)),
      ),
      child: Column(
        children: [
          _ProfileTile(
            icon: Icons.person_outline_rounded,
            iconBg: const Color(0xFFEEF4FF),
            iconColor: NataloColors.primary,
            label: 'Nama lengkap',
            value: profile.name.isNotEmpty ? profile.name : 'Belum diisi',
            onTap: () => _editText(
              context,
              title: 'Nama lengkap',
              hint: 'Masukkan nama lengkap',
              fieldKey: 'name',
              initial: profile.name,
            ),
          ),
          const _TileDivider(),
          _ProfileTile(
            icon: Icons.mail_outline_rounded,
            iconBg: const Color(0xFFFEF3E7),
            iconColor: const Color(0xFFF59E0B),
            label: 'Email',
            value: profile.email ?? 'Belum diisi',
            onTap: () => _editText(
              context,
              title: 'Email',
              hint: 'nama@email.com',
              fieldKey: 'email',
              initial: profile.email ?? '',
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const _TileDivider(),
          _ProfileTile(
            icon: Icons.phone_outlined,
            iconBg: const Color(0xFFE7F6EC),
            iconColor: const Color(0xFF16A34A),
            label: 'No. HP / WhatsApp',
            value: profile.phone ?? 'Belum diisi',
            onTap: () => _editText(
              context,
              title: 'No. HP / WhatsApp',
              hint: '08xxxxxxxxxx',
              fieldKey: 'phone',
              initial: profile.phone ?? '',
              keyboardType: TextInputType.phone,
            ),
          ),
          const _TileDivider(),
          _ProfileTile(
            icon: Icons.cake_outlined,
            iconBg: const Color(0xFFFCE7F3),
            iconColor: const Color(0xFFDB2777),
            label: 'Tanggal lahir',
            value: profile.birthDate != null
                ? formatTanggal(profile.birthDate!)
                : 'Belum diisi',
            onTap: () => _editBirthDate(context),
          ),
        ],
      ),
    );
  }
}

class _EditFieldSheet extends StatefulWidget {
  final String title;
  final String hint;
  final String initial;
  final TextInputType keyboardType;

  const _EditFieldSheet({
    required this.title,
    required this.hint,
    required this.initial,
    required this.keyboardType,
  });

  @override
  State<_EditFieldSheet> createState() => _EditFieldSheetState();
}

class _EditFieldSheetState extends State<_EditFieldSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8DEE7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: const TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              keyboardType: widget.keyboardType,
              autofocus: true,
              inputFormatters: [
                LengthLimitingTextInputFormatter(100),
              ],
              decoration: InputDecoration(
                hintText: widget.hint,
                filled: true,
                fillColor: const Color(0xFFF6F8FC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _ctrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NataloColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Simpan',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
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

// ────────────────────────── QUICK ACTIONS GRID ──────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = <_QuickActionItem>[
      _QuickActionItem(
        icon: Icons.location_on_outlined,
        label: 'Alamat',
        color: const Color(0xFFEF4444),
        route: '/member/addresses',
      ),
      _QuickActionItem(
        icon: Icons.confirmation_number_outlined,
        label: 'Voucher',
        color: const Color(0xFF16A34A),
        route: '/member/vouchers',
      ),
      _QuickActionItem(
        icon: Icons.stars_outlined,
        label: 'Poin',
        color: const Color(0xFFF59E0B),
        route: '/member/loyalty',
      ),
      _QuickActionItem(
        icon: Icons.video_library_outlined,
        label: 'Postingan',
        color: const Color(0xFF7C3AED),
        route: '/member/posts',
      ),
      _QuickActionItem(
        icon: Icons.reviews_outlined,
        label: 'Ulasan',
        color: const Color(0xFF0EA5E9),
        route: '/member/reviews',
      ),
      _QuickActionItem(
        icon: Icons.notifications_outlined,
        label: 'Notifikasi',
        color: const Color(0xFF6366F1),
        route: '/notifications/preferences',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8F8)),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.0,
        children: items.map((item) => _QuickActionTile(item: item)).toList(),
      ),
    );
  }
}

class _QuickActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final String route;

  _QuickActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QuickActionItem item;
  const _QuickActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        AppHaptics.tap();
        Navigator.pushNamed(context, item.route);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            item.label,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────── ACCOUNT SECURITY ──────────────────────────

class _AccountSecurityGroup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8F8)),
      ),
      child: Column(
        children: [
          _LinkRowTile(
            icon: Icons.lock_outline_rounded,
            iconColor: NataloColors.primary,
            label: 'Ganti password',
            onTap: () => Navigator.pushNamed(context, '/account/settings'),
          ),
          const _TileDivider(),
          _LinkRowTile(
            icon: Icons.security_rounded,
            iconColor: const Color(0xFF6366F1),
            label: 'Keamanan akun',
            onTap: () => Navigator.pushNamed(context, '/account/security'),
          ),
          const _TileDivider(),
          _LinkRowTile(
            icon: Icons.notifications_outlined,
            iconColor: const Color(0xFFF59E0B),
            label: 'Preferensi notifikasi',
            onTap: () =>
                Navigator.pushNamed(context, '/notifications/preferences'),
          ),
        ],
      ),
    );
  }
}

class _LinkRowTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _LinkRowTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: NataloColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: NataloColors.textTertiary,
      ),
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
    );
  }
}

// ────────────────────────── PROFILE TILE ──────────────────────────

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ProfileTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: NataloColors.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: NataloColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      trailing: onTap != null
          ? const Icon(
              Icons.edit_outlined,
              size: 18,
              color: NataloColors.textTertiary,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFF1F5F9),
      indent: 64,
      endIndent: 20,
    );
  }
}

// ────────────────────────── LOGOUT BUTTON ──────────────────────────

class _LogoutButton extends StatelessWidget {
  Future<void> _confirmLogout(BuildContext context) async {
    AppHaptics.tap();
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Keluar dari akun?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Kamu perlu login ulang untuk akses keranjang, pesanan, dan favorit.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text(
              'Keluar',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !context.mounted) return;
    await memberStore.logout();
    if (!context.mounted) return;
    AppHaptics.success();
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => _confirmLogout(context),
        icon: const Icon(
          Icons.logout_rounded,
          color: Color(0xFFEF4444),
          size: 18,
        ),
        label: const Text(
          'Keluar dari akun',
          style: TextStyle(
            color: Color(0xFFEF4444),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFFCE5E5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _AppVersionFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          'Natalo Petshop • v1.0',
          style: TextStyle(
            color: NataloColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────── NOT LOGGED IN ──────────────────────────

class _NotLoggedInState extends StatelessWidget {
  const _NotLoggedInState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: NataloColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 48,
                color: NataloColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum login',
              style: TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Login untuk melihat profil, poin, voucher, dan pesanan kamu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 46,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/member/login'),
                style: FilledButton.styleFrom(
                  backgroundColor: NataloColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Login Sekarang',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
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
