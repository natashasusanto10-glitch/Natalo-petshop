import 'package:flutter/material.dart';

import '../constants/official_brand.dart';
import '../models/public_profile.dart';
import '../state/member_store.dart';
import 'public_profile_follow_list_screen.dart';

/// Daftar follower milik sendiri via named-route (deep-link
/// /akun/followers dari notif follow agregat). Kalau belum login /
/// profil belum ter-hydrate → redirect ke /member.
class OwnFollowersScreen extends StatelessWidget {
  const OwnFollowersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    if (profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/member');
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final isOfficial = profile.isAdmin;
    return PublicProfileFollowListScreen(
      profile: PublicProfile(
        id: profile.id,
        name: isOfficial ? kOfficialBrandName : profile.name,
        username: profile.username,
        profilePhotoUrl: profile.profilePhotoUrl,
        bio: profile.bio,
        postCount: 0,
        followersCount: profile.followersCount,
        followingCount: profile.followingCount,
        isOwner: true,
        isOfficial: isOfficial,
      ),
      initialKind: FollowListKind.followers,
    );
  }
}
