import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

const _bg = Color(0xFF070B10);
const _searchFill = Color(0xFF242A30);
const _divider = Color(0xFF141A22);
const _muted = Color(0xFF8D96A3);
const _text = Color(0xFFF8FAFC);
const _brandBlue = Color(0xFF0B7FEA);
const _recentStorageKey = 'feed_user_search_recent_v1';
const _maxRecentUsers = 12;

class FeedUserSearchScreen extends StatefulWidget {
  const FeedUserSearchScreen({super.key});

  @override
  State<FeedUserSearchScreen> createState() => _FeedUserSearchScreenState();
}

class _FeedUserSearchScreenState extends State<FeedUserSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Set<String> _busyUserIds = <String>{};
  Timer? _debounce;
  String _query = '';
  String _lastRunQuery = '';
  bool _loading = false;
  bool _loginRequired = false;
  String? _error;
  List<FollowUserSummary> _items = const [];
  bool _suggestedLoading = false;
  List<FollowUserSummary> _recentUsers = const [];
  List<FollowUserSummary> _suggestedUsers = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
    _loadRecentUsers();
    _loadSuggestedUsers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final next = _controller.text.trim();
    if (next == _query) return;
    _debounce?.cancel();
    setState(() {
      _query = next;
      _error = null;
      _loginRequired = false;
      if (next.length < 2) {
        _lastRunQuery = '';
        _items = const [];
        _loading = false;
      }
    });
    if (next.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(next);
    });
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim().toLowerCase();
    if (q.length < 2) return;
    _lastRunQuery = q;
    setState(() {
      _loading = true;
      _error = null;
      _loginRequired = false;
    });
    try {
      final items = await followService.searchUsers(q, limit: 20);
      if (!mounted || _lastRunQuery != q || _normalizedQuery != q) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted || _lastRunQuery != q || _normalizedQuery != q) return;
      if (error is ApiException && error.statusCode == 401) {
        setState(() {
          _loginRequired = true;
          _items = const [];
        });
      } else {
        setState(() {
          _error = 'Pencarian belum berhasil. Coba lagi.';
          _items = const [];
        });
      }
    } finally {
      if (mounted && _lastRunQuery == q && _normalizedQuery == q) {
        setState(() => _loading = false);
      }
    }
  }

  String get _normalizedQuery => _controller.text.trim().toLowerCase();

  void _clear() {
    AppHaptics.tap();
    _controller.clear();
  }

  void _cancel() {
    AppHaptics.tap();
    Navigator.pop(context);
  }

  Future<void> _loadRecentUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_recentStorageKey) ?? const <String>[];
    final users = <FollowUserSummary>[];
    for (final raw in stored) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final user = FollowUserSummary.fromJson(decoded);
          if (user.canOpenProfile) users.add(user);
        } else if (decoded is Map) {
          final user = FollowUserSummary.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (user.canOpenProfile) users.add(user);
        }
      } catch (_) {
        // Abaikan entry lama yang rusak supaya recent tetap bisa tampil.
      }
    }
    if (!mounted) return;
    setState(() => _recentUsers = users.take(_maxRecentUsers).toList());
  }

  Future<void> _loadSuggestedUsers() async {
    setState(() => _suggestedLoading = true);
    try {
      final users = await followService.fetchSuggestedUsers(limit: 12);
      if (!mounted) return;
      setState(() => _suggestedUsers = users);
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestedUsers = const []);
    } finally {
      if (mounted) setState(() => _suggestedLoading = false);
    }
  }

  Future<void> _persistRecentUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentStorageKey,
      _recentUsers.map((user) => jsonEncode(user.toJson())).toList(),
    );
  }

  Future<void> _rememberRecentUser(FollowUserSummary user) async {
    if (!user.canOpenProfile) return;
    setState(() {
      final next = <FollowUserSummary>[
        user,
        ..._recentUsers.where((item) => item.id != user.id),
      ];
      _recentUsers = next.take(_maxRecentUsers).toList(growable: false);
    });
    await _persistRecentUsers();
  }

  Future<void> _removeRecentUser(FollowUserSummary user) async {
    AppHaptics.tap();
    setState(() {
      _recentUsers = _recentUsers
          .where((item) => item.id != user.id)
          .toList(growable: false);
    });
    await _persistRecentUsers();
  }

  Future<void> _clearRecentUsers() async {
    AppHaptics.tap();
    setState(() => _recentUsers = const []);
    await _persistRecentUsers();
  }

  void _openProfile(FollowUserSummary user) {
    final username = user.username;
    if (username == null || username.isEmpty) return;
    AppHaptics.tap();
    unawaited(_rememberRecentUser(user));
    Navigator.pushNamed(context, '/u', arguments: username);
  }

  Future<void> _toggleFollow(FollowUserSummary user) async {
    if (user.isSelf || _busyUserIds.contains(user.id)) return;
    AppHaptics.impact();
    final wasFollowing = user.isFollowing;
    final optimistic = user.copyWith(
      isFollowing: !wasFollowing,
      followersCount: wasFollowing
          ? (user.followersCount - 1).clamp(0, 999999)
          : user.followersCount + 1,
    );
    setState(() {
      _busyUserIds.add(user.id);
      _replaceUserEverywhere(optimistic);
    });
    if (_recentUsers.any((item) => item.id == user.id)) {
      unawaited(_persistRecentUsers());
    }
    try {
      final state = wasFollowing
          ? await followService.unfollow(user.id)
          : await followService.follow(user.id);
      if (!mounted) return;
      final updated = optimistic.copyWith(
        isFollowing: state.isFollowing,
        followersCount: state.followersCount,
        followingCount: state.followingCount,
        isSelf: state.isSelf,
      );
      setState(() => _replaceUserEverywhere(updated));
      if (_recentUsers.any((item) => item.id == user.id)) {
        unawaited(_persistRecentUsers());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _replaceUserEverywhere(user));
      if (_recentUsers.any((item) => item.id == user.id)) {
        unawaited(_persistRecentUsers());
      }
      AppToast.show(context, 'Gagal update follow. Coba lagi.');
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(user.id));
      }
    }
  }

  void _replaceUserEverywhere(FollowUserSummary user) {
    _items = _replaceUser(_items, user);
    _recentUsers = _replaceUser(_recentUsers, user);
    _suggestedUsers = _replaceUser(_suggestedUsers, user);
  }

  List<FollowUserSummary> _replaceUser(
    List<FollowUserSummary> users,
    FollowUserSummary user,
  ) {
    var changed = false;
    final next = users.map((item) {
      if (item.id != user.id) return item;
      changed = true;
      return user;
    }).toList(growable: false);
    return changed ? next : users;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _SearchHeader(
                controller: _controller,
                focusNode: _focusNode,
                hasText: _query.isNotEmpty,
                onClear: _clear,
                onCancel: _cancel,
                onSubmitted: (_) => _focusNode.unfocus(),
              ),
              const Divider(height: 1, thickness: 0.5, color: _divider),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.length < 2) {
      return _buildDefaultBody();
    }
    if (_loginRequired) {
      return _MessageState(
        icon: Icons.lock_outline_rounded,
        title: 'Login untuk cari akun',
        body: 'Masuk dulu supaya bisa menemukan dan follow akun Natalo.',
        actionLabel: 'Login',
        onAction: () => Navigator.pushNamed(context, '/member/login'),
      );
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.search_off_rounded,
        title: 'Pencarian gagal',
        body: _error!,
        actionLabel: 'Coba lagi',
        onAction: () => _runSearch(_query),
      );
    }
    if (_loading && _items.isEmpty) {
      return const _SearchSkeletonList();
    }
    if (!_loading && _items.isEmpty) {
      return _MessageState(
        icon: Icons.person_search_rounded,
        title: 'Akun tidak ditemukan',
        body: 'Coba username atau nama lain.',
        query: _query,
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const _SectionHeader(title: 'Hasil pencarian'),
        for (final user in _items)
          _UserResultTile(
            user: user,
            busy: _busyUserIds.contains(user.id),
            onTap: () => _openProfile(user),
            onFollowTap: user.isSelf ? null : () => _toggleFollow(user),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDefaultBody() {
    final children = <Widget>[];

    if (_recentUsers.isNotEmpty) {
      children
        ..add(
          _SectionHeader(
            title: 'Recent',
            actionLabel: 'Hapus',
            onAction: () => _clearRecentUsers(),
          ),
        )
        ..addAll(
          _recentUsers.map(
            (user) => _UserResultTile(
              user: user,
              busy: _busyUserIds.contains(user.id),
              onTap: () => _openProfile(user),
              onFollowTap: user.isSelf ? null : () => _toggleFollow(user),
              onRemove: () => _removeRecentUser(user),
            ),
          ),
        )
        ..add(const SizedBox(height: 14));
    }

    if (_suggestedLoading && _suggestedUsers.isEmpty) {
      children
        ..add(const _SectionHeader(title: 'Akun yang mungkin kamu kenal'))
        ..addAll(List.generate(4, (_) => const _SkeletonRow()));
    } else if (_suggestedUsers.isNotEmpty) {
      children
        ..add(const _SectionHeader(title: 'Akun yang mungkin kamu kenal'))
        ..addAll(
          _suggestedUsers.map(
            (user) => _UserResultTile(
              user: user,
              busy: _busyUserIds.contains(user.id),
              onTap: () => _openProfile(user),
              onFollowTap: user.isSelf ? null : () => _toggleFollow(user),
            ),
          ),
        );
    }

    if (children.isEmpty) {
      return const _MessageState(
        icon: Icons.person_search_rounded,
        title: 'Cari akun',
        body: 'Mulai ketik username atau nama.',
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: children,
    );
  }
}

class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onClear;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmitted;

  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onClear,
    required this.onCancel,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: _searchFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                keyboardAppearance: Brightness.dark,
                cursorColor: _text,
                textInputAction: TextInputAction.search,
                onSubmitted: onSubmitted,
                inputFormatters: [LengthLimitingTextInputFormatter(60)],
                style: const TextStyle(
                  color: _text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  hintText: 'Cari akun',
                  hintStyle: const TextStyle(
                    color: _muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _muted,
                    size: 24,
                  ),
                  suffixIcon: hasText
                      ? IconButton(
                          tooltip: 'Hapus',
                          onPressed: onClear,
                          icon: const Icon(
                            Icons.cancel_rounded,
                            color: _muted,
                            size: 19,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Batal',
                style: TextStyle(
                  color: _text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: _brandBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  final FollowUserSummary user;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onFollowTap;
  final VoidCallback? onRemove;

  const _UserResultTile({
    required this.user,
    required this.busy,
    required this.onTap,
    required this.onFollowTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final username = user.username ?? user.name;
    final subtitle = user.name.isNotEmpty && user.name != username
        ? user.name
        : '${_formatCount(user.followersCount)} pengikut';
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            _Avatar(user: user),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (onRemove != null)
              IconButton(
                tooltip: 'Hapus dari recent',
                onPressed: onRemove,
                icon: const Icon(
                  Icons.close_rounded,
                  color: _muted,
                  size: 22,
                ),
              )
            else if (user.isSelf)
              const Text(
                'Kamu',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              _FollowButton(
                following: user.isFollowing,
                busy: busy,
                onTap: onFollowTap,
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final FollowUserSummary user;

  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final url = user.profilePhotoUrl;
    return ClipOval(
      child: Container(
        width: 56,
        height: 56,
        color: const Color(0xFF1B2330),
        alignment: Alignment.center,
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (_, __) => _Initial(initial: user.initial),
                errorWidget: (_, __, ___) => _Initial(initial: user.initial),
              )
            : _Initial(initial: user.initial),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String initial;

  const _Initial({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Text(
      initial,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool following;
  final bool busy;
  final VoidCallback? onTap;

  const _FollowButton({
    required this.following,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = following ? 'Mengikuti' : 'Ikuti';
    return SizedBox(
      height: 34,
      child: following
          ? OutlinedButton(
              onPressed: busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _text,
                disabledForegroundColor: _muted,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _ButtonContent(
                label: label,
                busy: busy,
                spinnerColor: _text,
              ),
            )
          : FilledButton(
              onPressed: busy ? null : onTap,
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
                disabledBackgroundColor: _brandBlue.withValues(alpha: 0.65),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _ButtonContent(
                label: label,
                busy: busy,
                spinnerColor: Colors.white,
              ),
            ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final String label;
  final bool busy;
  final Color spinnerColor;

  const _ButtonContent({
    required this.label,
    required this.busy,
    required this.spinnerColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!busy) return Text(label);
    return SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: spinnerColor,
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? query;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.body,
    this.query,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.52), size: 44),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              query == null ? body : '$body\n"$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
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

class _SearchSkeletonList extends StatelessWidget {
  const _SearchSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: 6,
      itemBuilder: (_, __) => const _SkeletonRow(),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _SkeletonCircle(),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBar(width: 128),
                SizedBox(height: 8),
                _SkeletonBar(width: 190, opacity: 0.09),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  const _SkeletonCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double opacity;

  const _SkeletonBar({required this.width, this.opacity = 0.13});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

String _formatCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}jt';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}rb';
  }
  return '$count';
}
