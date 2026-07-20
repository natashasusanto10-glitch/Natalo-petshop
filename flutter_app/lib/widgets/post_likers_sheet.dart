import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';

import '../screens/public_profile_screen.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../state/follow_override_store.dart';
import 'app_toast.dart';
import 'official_brand_avatar.dart';
import '../services/post_likers_service.dart';
import '../utils/haptics.dart';
import 'profile_avatar.dart';
import '../constants/official_brand.dart';

const _brandBlue = NataloColors.primary;

/// IG-style "Disukai oleh" bottom sheet — list user yang like sebuah
/// post, dengan tombol Follow/Mengikuti per row + tap baris untuk buka
/// public profile.
///
/// Open via `PostLikersSheet.show(context, postId: ...)`. Sheet handle
/// fetch awal + infinite scroll + optimistic follow toggle internally.
class PostLikersSheet extends StatefulWidget {
  final String postId;

  const PostLikersSheet({super.key, required this.postId});

  /// Helper untuk show sheet sebagai modal bottom sheet dengan
  /// DraggableScrollableSheet — match IG behavior dimana user bisa
  /// drag-up untuk expand atau drag-down untuk close.
  static Future<void> show(BuildContext context, {required String postId}) {
    AppHaptics.tap();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _Container(
            child: PostLikersSheet(postId: postId),
          );
        },
      ),
    );
  }

  @override
  State<PostLikersSheet> createState() => _PostLikersSheetState();
}

class _PostLikersSheetState extends State<PostLikersSheet> {
  final ScrollController _scrollController = ScrollController();
  List<FollowUserSummary> _items = [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _errorText;
  // Track follow-in-flight per userId — guard double-tap + show progress.
  final Set<String> _followBusy = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _nextCursor == null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final result = await postLikersService.fetchLikers(widget.postId);
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _nextCursor = result.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'Gagal memuat daftar. Coba lagi.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await postLikersService.fetchLikers(
        widget.postId,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...result.items];
        _nextCursor = result.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow(int index) async {
    final liker = _items[index];
    if (liker.isSelf || _followBusy.contains(liker.id)) return;
    AppHaptics.tap();

    final wasFollowing = liker.isFollowing;
    setState(() {
      _followBusy.add(liker.id);
      _items[index] = liker.copyWith(isFollowing: !wasFollowing);
    });
    setFollowOverride(liker.id, !wasFollowing);

    try {
      final state = wasFollowing
          ? await followService.unfollow(liker.id)
          : await followService.follow(liker.id);
      if (!mounted) return;
      setState(() {
        _followBusy.remove(liker.id);
        // Sync dari server response — covers concurrent toggle race.
        _items[index] = _items[index].copyWith(
          isFollowing: state.isFollowing,
          followersCount: state.followersCount,
        );
      });
      setFollowOverride(liker.id, state.isFollowing);
    } on FollowSessionChangedException {
      if (mounted) setState(() => _followBusy.remove(liker.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      final stableFollowing = resolveFollowState(liker.id, wasFollowing);
      final stableFollowers = (liker.followersCount +
              (stableFollowing == wasFollowing
                  ? 0
                  : stableFollowing
                      ? 1
                      : -1))
          .clamp(0, 1 << 30);
      setState(() {
        _followBusy.remove(liker.id);
        _items[index] = _items[index].copyWith(
          isFollowing: stableFollowing,
          followersCount: stableFollowers,
        );
      });
      if (e.isUnauthorized) {
        Navigator.pop(context);
        Navigator.pushNamed(context, '/member/login');
      } else {
        // ApiException dari follow/unfollow gagal → error.
        AppToast.showBanner(context, e.message, kind: ToastKind.error);
      }
    } catch (_) {
      if (!mounted) return;
      final stableFollowing = resolveFollowState(liker.id, wasFollowing);
      final stableFollowers = (liker.followersCount +
              (stableFollowing == wasFollowing
                  ? 0
                  : stableFollowing
                      ? 1
                      : -1))
          .clamp(0, 1 << 30);
      setState(() {
        _followBusy.remove(liker.id);
        _items[index] = _items[index].copyWith(
          isFollowing: stableFollowing,
          followersCount: stableFollowers,
        );
      });
    }
  }

  void _openProfile(FollowUserSummary liker) {
    if (!liker.canOpenProfile) return;
    AppHaptics.tap();
    // Pop sheet first supaya stack tidak menumpuk (kalau user buka profile
    // dari sheet, lalu back, langsung balik ke post detail — bukan ke
    // sheet terbuka di atas profile).
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: liker.username!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(),
        _buildHeader(),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHandle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Disukai oleh',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tutup',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: _brandBlue,
          strokeWidth: 2.4,
        ),
      );
    }
    if (_errorText != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: _brandBlue),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Belum ada yang menyukai postingan ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _LikerRow(
          liker: _items[index],
          busy: _followBusy.contains(_items[index].id),
          onTap: () => _openProfile(_items[index]),
          onToggleFollow: () => _toggleFollow(index),
        );
      },
    );
  }
}

class _Container extends StatelessWidget {
  final Widget child;

  const _Container({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _LikerRow extends StatelessWidget {
  final FollowUserSummary liker;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onToggleFollow;

  const _LikerRow({
    required this.liker,
    required this.busy,
    required this.onTap,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: liker.canOpenProfile ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _Avatar(liker: liker),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          // Official → brand name "Natalo Petshop" (emas);
                          // user biasa → username.
                          liker.isOfficial
                              ? kOfficialBrandName
                              : (liker.username != null &&
                                      liker.username!.isNotEmpty
                                  ? liker.username!
                                  : liker.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: liker.isOfficial
                                ? NataloColors.officialGoldOnLight
                                : cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                      if (liker.isOfficial) ...[
                        const SizedBox(width: 4),
                        const OfficialVerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    liker.isOfficial ? kOfficialBrandName : liker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!liker.isSelf)
              _FollowButton(
                isFollowing: liker.isFollowing,
                busy: busy,
                onPressed: onToggleFollow,
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final FollowUserSummary liker;

  const _Avatar({required this.liker});

  @override
  Widget build(BuildContext context) {
    const size = 42.0;
    return ProfileAvatar(
      initial: liker.initial,
      imageUrl: liker.profilePhotoUrl,
      size: size,
      fontSize: 16,
      isOfficial: liker.isOfficial,
      plain: true,
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool busy;
  final VoidCallback onPressed;

  const _FollowButton({
    required this.isFollowing,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // IG-style compact button: Follow = brand blue filled, Mengikuti =
    // outlined neutral. Width fixed supaya tidak shift size saat toggle.
    final width = isFollowing ? 96.0 : 80.0;
    if (isFollowing) {
      return SizedBox(
        width: width,
        height: 32,
        child: OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outlineVariant),
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              : const Text('Mengikuti'),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: 32,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _brandBlue,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text('Ikuti'),
      ),
    );
  }
}
