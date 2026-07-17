import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import 'public_profile_content_tab_bar.dart';
import 'public_profile_expanded_header.dart';
import 'public_profile_header_motion.dart';

/// Bagian header profil publik yang MENYUSUT (dipasang sebagai isi
/// [CollapsingHeaderDelegate.builder]): identity (avatar/bio/tombol) di
/// atas, tab bar (Postingan/Video/Belanja) tetap di baris paling bawah.
///
/// Tab bar TIDAK PERNAH berpindah posisi secara independen — begitu
/// identity di atasnya habis menyusut (t=1), tab bar otomatis berada di
/// posisi finalnya sebagai konsekuensi alami Column yang mengecil, bukan
/// animasi posisi terpisah. Alas kaca pill (dan fade label→ikon) memakai
/// `t` yang SAMA PERSIS dengan penyusutan identity, sehingga tidak pernah
/// ada frame di mana tab sudah "sampai" tapi alasnya belum muncul.
class PublicProfileIdentityTabHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final bool chatEnabled;
  final TabController tabController;
  final double identityHeight;
  final double tabHeight;
  final double t;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;
  final ValueChanged<int>? onTabTap;

  const PublicProfileIdentityTabHeader({
    super.key,
    required this.profile,
    required this.followBusy,
    required this.chatEnabled,
    required this.tabController,
    required this.identityHeight,
    required this.tabHeight,
    required this.t,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
    this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final motion = PublicProfileHeaderMotion.resolve(
      t: t,
      reducedMotion: reducedMotion,
    );
    // Identity height mengecil LINEAR dari identityHeight ke 0 mengikuti t —
    // syarat wajib CollapsingHeaderDelegate (lihat dokumentasi delegate itu).
    final shrunkIdentityHeight = identityHeight * (1 - t);
    final identityOpacity = (1 - t * 1.4).clamp(0.0, 1.0).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: shrunkIdentityHeight,
          child: ClipRect(
            child: OverflowBox(
              maxHeight: identityHeight,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: identityOpacity,
                child: PublicProfileExpandedHeader(
                  profile: profile,
                  followBusy: followBusy,
                  chatEnabled: chatEnabled,
                  onFollowToggle: onFollowToggle,
                  onFollowersTap: onFollowersTap,
                  onFollowingTap: onFollowingTap,
                  onEditProfile: onEditProfile,
                  onShareProfile: onShareProfile,
                  onMessage: onMessage,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          key: const Key('public_profile_tab_group'),
          height: tabHeight,
          child: PublicProfileContentTabBar(
            controller: tabController,
            labelOpacity: motion.labelOpacity,
            pillOpacity: motion.pillOpacity,
            underlineOpacity: motion.underlineOpacity,
            reducedMotion: reducedMotion,
            onTap: onTabTap,
          ),
        ),
      ],
    );
  }
}
