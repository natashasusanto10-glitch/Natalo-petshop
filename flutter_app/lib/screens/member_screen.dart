import 'package:flutter/material.dart';

import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import 'login_screen.dart';

/// Hub akun member: profile + nav ke pesanan, voucher, loyalty, dst.
class MemberScreen extends StatelessWidget {
  const MemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        final profile = memberStore.profile;
        if (profile == null) {
          return const LoginScreen();
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Akun Saya')),
          body: ListView(
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: NataloColors.primary,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text(profile.name),
                subtitle: Text(profile.email ?? profile.phone ?? ''),
                onTap: () => Navigator.pushNamed(context, '/member/profile'),
              ),
              const Divider(),
              _tile(
                context,
                Icons.receipt_long,
                'Pesanan Saya',
                '/member/orders',
              ),
              _tile(
                context,
                Icons.location_on_outlined,
                'Alamat',
                '/member/addresses',
              ),
              _tile(
                context,
                Icons.local_offer_outlined,
                'Voucher',
                '/member/vouchers',
              ),
              _tile(
                context,
                Icons.workspace_premium_outlined,
                'Loyalty',
                '/member/loyalty',
              ),
              _tile(
                context,
                Icons.video_collection_outlined,
                'Postingan Saya',
                '/member/postingan',
              ),
              _tile(
                  context, Icons.reviews_outlined, 'Ulasan', '/member/reviews'),
              _tile(
                context,
                Icons.settings_outlined,
                'Pengaturan',
                '/account/settings',
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: NataloColors.danger),
                title: const Text(
                  'Keluar',
                  style: TextStyle(color: NataloColors.danger),
                ),
                onTap: () async {
                  await memberStore.logout();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (_) => false,
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(
      BuildContext context, IconData icon, String label, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}
