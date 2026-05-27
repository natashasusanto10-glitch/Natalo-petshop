import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import '../services/follow_service.dart';
import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _darkNavy = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _borderSoft = Color(0xFFE2E8F0);

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialKind == FollowListKind.followers ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _darkNavy,
            size: 26,
          ),
          tooltip: 'Kembali',
        ),
        title: Text(
          profile.displayHandle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _darkNavy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: _borderSoft, width: 0.5),
                bottom: BorderSide(color: _borderSoft, width: 0.5),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: _darkNavy,
              unselectedLabelColor: _textSecondary,
              indicatorColor: _darkNavy,
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
                Tab(text: 'Pengikut ${profile.followersCount}'),
                Tab(text: 'Mengikuti ${profile.followingCount}'),
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
          ),
          _FollowListPane(
            profile: profile,
            kind: FollowListKind.following,
          ),
        ],
      ),
    );
  }
}

class _FollowListPane extends StatefulWidget {
  final PublicProfile profile;
  final FollowListKind kind;

  const _FollowListPane({
    required this.profile,
    required this.kind,
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

  void _openUser(FollowUserSummary user) {
    if (!user.canOpenProfile) return;
    AppHaptics.tap();
    Navigator.pushNamed(context, '/u', arguments: user.username);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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

    return RefreshIndicator(
      color: _brandBlue,
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          thickness: 0.5,
          color: _borderSoft,
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
            onTap: user.canOpenProfile ? () => _openUser(user) : null,
          );
        },
      ),
    );
  }
}

class _FollowUserTile extends StatelessWidget {
  final FollowUserSummary user;
  final VoidCallback? onTap;

  const _FollowUserTile({
    required this.user,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (user.username != null && user.username!.isNotEmpty) user.username!,
      if (user.bio != null && user.bio!.isNotEmpty) user.bio!,
    ].join(' - ');

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
                    style: const TextStyle(
                      color: _darkNavy,
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
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (user.canOpenProfile) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _darkNavy,
                  side: const BorderSide(color: _borderSoft),
                  minimumSize: const Size(64, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Lihat'),
              ),
            ],
          ],
        ),
      ),
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
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFEFF6FF),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: const Color(0xFFCBD5E1),
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _darkNavy,
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
