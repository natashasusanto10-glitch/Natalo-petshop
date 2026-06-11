import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';

const _brandBlue = Color(0xFF0B7FEA);

enum FollowListKind {
  followers,
  following,
}

class PublicProfileFollowListScreen extends StatefulWidget {
  final PublicProfile profile;
  final FollowListKind initialKind;

  const PublicProfileFollowListScreen({
    super.key,
    required this.profile,
    required this.initialKind,
  });

  @override
  State<PublicProfileFollowListScreen> createState() =>
      _PublicProfileFollowListScreenState();
}

class _PublicProfileFollowListScreenState
    extends State<PublicProfileFollowListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late int _followersCount;
  late int _followingCount;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialKind == FollowListKind.followers ? 0 : 1,
    );
    _followersCount = widget.profile.followersCount;
    _followingCount = widget.profile.followingCount;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: cs.onSurface,
            size: 26,
          ),
          tooltip: 'Kembali',
        ),
        title: Text(
          profile.displayHandle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
                bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: cs.onSurface,
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              tabs: [
                Tab(text: 'Pengikut $_followersCount'),
                Tab(text: 'Mengikuti $_followingCount'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FollowListPane(
            profile: profile,
            kind: FollowListKind.followers,
            onFollowChanged: _handleFollowChanged,
          ),
          _FollowListPane(
            profile: profile,
            kind: FollowListKind.following,
            onFollowChanged: _handleFollowChanged,
          ),
        ],
      ),
    );
  }

  void _handleFollowChanged(
    FollowUserSummary user,
    FollowState state,
    bool wasFollowing,
  ) {
    if (user.id == widget.profile.id) {
      setState(() {
        _followersCount = state.followersCount;
      });
      return;
    }

    final viewerId = memberStore.profile?.id;
    if (viewerId == widget.profile.id && wasFollowing != state.isFollowing) {
      setState(() {
        _followingCount += state.isFollowing ? 1 : -1;
        if (_followingCount < 0) _followingCount = 0;
      });
    }
  }
}

class _FollowListPane extends StatefulWidget {
  final PublicProfile profile;
  final FollowListKind kind;
  final void Function(
          FollowUserSummary user, FollowState state, bool wasFollowing)
      onFollowChanged;

  const _FollowListPane({
    required this.profile,
    required this.kind,
    required this.onFollowChanged,
  });

  @override
  State<_FollowListPane> createState() => _FollowListPaneState();
}

class _FollowListPaneState extends State<_FollowListPane>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<FollowUserSummary> _items = const [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _errorText;
  final Set<String> _busyUserIds = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || _nextCursor == null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 360) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final result = await _fetch();
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
        _errorText = 'Gagal memuat ${_kindLabel.toLowerCase()}.';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _fetch(cursor: cursor);
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

  Future<FollowListResult> _fetch({String? cursor}) {
    return widget.kind == FollowListKind.followers
        ? followService.fetchFollowers(widget.profile.id, cursor: cursor)
        : followService.fetchFollowing(widget.profile.id, cursor: cursor);
  }

  Future<void> _refresh() async => _load();

  String get _kindLabel =>
      widget.kind == FollowListKind.followers ? 'Pengikut' : 'Mengikuti';

  String get _emptyText => widget.kind == FollowListKind.followers
      ? 'Belum ada pengikut'
      : 'Belum mengikuti user lain';

  Future<void> _openUser(FollowUserSummary user) async {
    if (!user.canOpenProfile) return;
    AppHaptics.tap();
    await Navigator.pushNamed(context, '/u', arguments: user.username);
    if (mounted) _load();
  }

  Future<void> _toggleFollow(FollowUserSummary user) async {
    if (user.isSelf || _busyUserIds.contains(user.id)) return;
    AppHaptics.tap();
    if (!memberStore.isLoggedIn) {
      Navigator.pushNamed(context, '/member/login');
      return;
    }

    final wasFollowing = user.isFollowing;
    final optimistic = user.copyWith(
      isFollowing: !wasFollowing,
      followersCount: _nonNegative(
        user.followersCount + (wasFollowing ? -1 : 1),
      ),
    );

    setState(() {
      _busyUserIds.add(user.id);
      _replaceUser(optimistic);
    });

    try {
      final state = wasFollowing
          ? await followService.unfollow(user.id)
          : await followService.follow(user.id);
      if (!mounted) return;
      final updated = user.copyWith(
        isFollowing: state.isFollowing,
        followersCount: state.followersCount,
        followingCount: state.followingCount,
      );
      setState(() {
        _busyUserIds.remove(user.id);
        _replaceUser(updated);
      });
      widget.onFollowChanged(updated, state, wasFollowing);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busyUserIds.remove(user.id);
        _replaceUser(user);
      });
      if (e.isUnauthorized) {
        Navigator.pushNamed(context, '/member/login');
      } else {
        _showSnack(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busyUserIds.remove(user.id);
        _replaceUser(user);
      });
      _showSnack('Gagal memproses follow. Coba lagi.');
    }
  }

  void _replaceUser(FollowUserSummary user) {
    _items = _items
        .map((item) => item.id == user.id ? user : item)
        .toList(growable: false);
  }

  int _nonNegative(int value) => value < 0 ? 0 : value;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
      return _FollowListMessage(
        icon: Icons.error_outline_rounded,
        title: _errorText!,
        actionLabel: 'Coba Lagi',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return _FollowListMessage(
        icon: Icons.people_outline_rounded,
        title: _emptyText,
      );
    }

    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          color: cs.outlineVariant,
          indent: 84,
        ),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                  color: _brandBlue,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          final user = _items[index];
          return _FollowUserTile(
            user: user,
            kind: widget.kind,
            followBusy: _busyUserIds.contains(user.id),
            onTap: user.canOpenProfile ? () => _openUser(user) : null,
            onFollowToggle: user.isSelf ? null : () => _toggleFollow(user),
          );
        },
      ),
    );
  }
}

class _FollowUserTile extends StatelessWidget {
  final FollowUserSummary user;
  final FollowListKind kind;
  final bool followBusy;
  final VoidCallback? onTap;
  final VoidCallback? onFollowToggle;

  const _FollowUserTile({
    required this.user,
    required this.kind,
    required this.followBusy,
    this.onTap,
    this.onFollowToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      if (user.username != null && user.username!.isNotEmpty) user.username!,
      if (user.bio != null && user.bio!.isNotEmpty) user.bio!,
    ].join(' - ');

    final followLabel = user.isSelf
        ? 'Kamu'
        : user.isFollowing
            ? 'Mengikuti'
            : kind == FollowListKind.followers
                ? 'Follow balik'
                : 'Follow';
    final useFilled = !user.isSelf && !user.isFollowing;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            _FollowAvatar(user: user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name.isEmpty ? user.displayHandle : user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (useFilled)
              FilledButton(
                onPressed: followBusy ? null : onFollowToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandBlue,
                  disabledBackgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size(92, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _FollowTileButtonContent(
                  label: followLabel,
                  busy: followBusy,
                  spinnerColor: Colors.white,
                ),
              )
            else
              OutlinedButton(
                onPressed: user.isSelf || followBusy ? null : onFollowToggle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  disabledForegroundColor:
                      user.isSelf ? cs.onSurfaceVariant : cs.onSurface,
                  side: BorderSide(
                    color: cs.outlineVariant,
                  ),
                  minimumSize: const Size(92, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _FollowTileButtonContent(
                  label: followLabel,
                  busy: followBusy,
                  spinnerColor: cs.onSurfaceVariant,
                ),
              ),
            if (user.canOpenProfile) ...[
              const SizedBox(width: 12),
              IconButton(
                onPressed: onTap,
                icon: const Icon(Icons.chevron_right_rounded),
                color: cs.onSurfaceVariant,
                tooltip: 'Lihat profil',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FollowTileButtonContent extends StatelessWidget {
  final String label;
  final bool busy;
  final Color spinnerColor;

  const _FollowTileButtonContent({
    required this.label,
    required this.busy,
    required this.spinnerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          ),
          const SizedBox(width: 7),
        ],
        Text(label),
      ],
    );
  }
}

class _FollowAvatar extends StatelessWidget {
  final FollowUserSummary user;

  const _FollowAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final url = user.profilePhotoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (_, __) => _initialAvatar(),
          errorWidget: (_, __, ___) => _initialAvatar(),
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    return Builder(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHighest,
          ),
          child: Center(
            child: Text(
              user.initial,
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FollowListMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FollowListMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: cs.onSurfaceVariant,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandBlue,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
