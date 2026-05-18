import 'package:flutter/material.dart';

import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Profile member — view personal data, link ke edit screen masing-masing
/// field, plus quick stats (points, orders count, dst).
class MemberProfileScreen extends StatelessWidget {
  const MemberProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Profil Saya'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: memberStore,
        builder: (context, _) {
          final profile = memberStore.profile;
          if (profile == null) {
            return _NotLoggedInState();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDDE8F8)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            NataloColors.primary,
                            NataloColors.primaryLight,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          profile.name.isNotEmpty
                              ? profile.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.name,
                            style: const TextStyle(
                              color: NataloColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (profile.email != null)
                            Text(
                              profile.email!,
                              style: const TextStyle(
                                color: NataloColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (profile.phone != null)
                            Text(
                              profile.phone!,
                              style: const TextStyle(
                                color: NataloColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDDE8F8)),
                ),
                child: Column(
                  children: [
                    _ProfileTile(
                      icon: Icons.person_outline_rounded,
                      label: 'Nama lengkap',
                      value: profile.name,
                      onTap: () => _editNotAvailable(context, 'Nama lengkap'),
                    ),
                    const _TileDivider(),
                    _ProfileTile(
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                      value: profile.email ?? '-',
                      onTap: () => _editNotAvailable(context, 'Email'),
                    ),
                    const _TileDivider(),
                    _ProfileTile(
                      icon: Icons.phone_outlined,
                      label: 'No. HP / WhatsApp',
                      value: profile.phone ?? '-',
                      onTap: () => _editNotAvailable(context, 'No. HP'),
                    ),
                    const _TileDivider(),
                    _ProfileTile(
                      icon: Icons.cake_outlined,
                      label: 'Tanggal lahir',
                      value: profile.birthDate != null
                          ? formatTanggal(profile.birthDate!)
                          : 'Belum diisi',
                      onTap: () =>
                          _editNotAvailable(context, 'Tanggal lahir'),
                    ),
                    const _TileDivider(),
                    _ProfileTile(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Role',
                      value: profile.role,
                      trailing: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDDE8F8)),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.lock_outline_rounded,
                    color: NataloColors.primary,
                  ),
                  title: const Text(
                    'Ganti Password',
                    style: TextStyle(
                      color: NataloColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    AppHaptics.tap();
                    Navigator.pushNamed(context, '/account/settings');
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Edit data profil sementara via PWA web — Flutter coming soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NataloColors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editNotAvailable(BuildContext context, String label) {
    AppHaptics.tap();
    AppToast.show(
      context,
      'Edit $label belum tersedia di Flutter.',
      kind: ToastKind.info,
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: NataloColors.primary, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          color: NataloColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          value,
          style: const TextStyle(
            color: NataloColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      trailing: trailing ??
          (onTap != null
              ? const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: NataloColors.textTertiary,
                )
              : null),
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
      indent: 20,
      endIndent: 20,
    );
  }
}

class _NotLoggedInState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 64,
              color: NataloColors.textTertiary,
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
              'Login untuk melihat profil Anda.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/member/login'),
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
