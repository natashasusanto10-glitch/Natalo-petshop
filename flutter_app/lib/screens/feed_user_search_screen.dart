import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../state/follow_override_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_avatar.dart';

const _bg = Color(0xFF070B10);
const _searchFill = Color(0xFF242A30);
const _divider = Color(0xFF141A22);
const _muted = Color(0xFF8D96A3);
const _text = Color(0xFFF8FAFC);
const _brandBlue = NataloColors.primary;
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
      // 6 (dari 12) — state awal harus sparse ala IG, bukan langsung
      // memenuhi layar sebelum user mengetik apa pun.
      final users = await followService.fetchSuggestedUsers(limit: 6);
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

  Future<void> _openProfile(FollowUserSummary user) async {
    final username = user.username;
    if (username == null || username.isEmpty) return;
    AppHaptics.tap();
    unawaited(_rememberRecentUser(user));
    await Navigator.pushNamed(context, '/u', arguments: username);
    if (!mounted) return;
    setState(() {
      List<FollowUserSummary> reconcile(List<FollowUserSummary> users) {
        return users
            .map((item) => item.copyWith(
                  isFollowing: resolveFollowState(item.id, item.isFollowing),
                ))
            .toList(growable: false);
      }

      _items = reconcile(_items);
      _recentUsers = reconcile(_recentUsers);
      _suggestedUsers = reconcile(_suggestedUsers);
    });
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
    setFollowOverride(user.id, !wasFollowing);
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
      setFollowOverride(user.id, state.isFollowing);
      if (_recentUsers.any((item) => item.id == user.id)) {
        unawaited(_persistRecentUsers());
      }
    } on FollowSessionChangedException {
      // The authenticated viewer changed. The new session owns all follow
      // state; do not roll back or publish the previous viewer's response.
    } catch (_) {
      if (!mounted) return;
      final stableFollowing = resolveFollowState(user.id, wasFollowing);
      final rollback = stableFollowing == optimistic.isFollowing
          ? optimistic
          : user.copyWith(isFollowing: stableFollowing);
      setState(() => _replaceUserEverywhere(rollback));
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
    // Hasil pencarian ala IG: baris polos TANPA tombol follow + tanpa
    // header section — follow dilakukan dari profil. Bikin hasil ringan.
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final user in _items)
          _UserResultTile(
            user: user,
            busy: _busyUserIds.contains(user.id),
            showFollow: false,
            onTap: () => _openProfile(user),
            onFollowTap: null,
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
      // Recent = rail avatar horizontal ala IG — hemat ruang vertikal
      // supaya state awal tetap sparse. Tap avatar → profil, × kecil di
      // pojok → hapus satu, "Hapus" di header → hapus semua.
      children
        ..add(
          _SectionHeader(
            title: 'Baru dilihat',
            actionLabel: 'Hapus',
            onAction: () => _clearRecentUsers(),
          ),
        )
        ..add(
          _RecentUserRail(
            users: _recentUsers,
            onOpen: _openProfile,
            onRemove: _removeRecentUser,
          ),
        )
        ..add(
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Divider(height: 1, thickness: 0.5, color: _divider),
          ),
        );
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
              height: 40,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _muted,
                    size: 22,
                  ),
                  suffixIcon: hasText
                      ? IconButton(
                          tooltip: 'Hapus',
                          onPressed: onClear,
                          icon: const Icon(
                            Icons.cancel_rounded,
                            color: _muted,
                            size: 18,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
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
    // Header section muted kecil ala IG ("Suggested for you") — bukan
    // judul putih besar w900 yang bikin halaman terasa berat.
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600,
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

  /// false = baris polos ala hasil pencarian IG (tanpa tombol follow —
  /// follow dilakukan dari profil). true = baris saran dengan tombol.
  final bool showFollow;

  const _UserResultTile({
    required this.user,
    required this.busy,
    required this.onTap,
    required this.onFollowTap,
    this.showFollow = true,
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Row(
          children: [
            _Avatar(user: user),
            const SizedBox(width: 12),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            if (showFollow) ...[
              const SizedBox(width: 12),
              if (user.isSelf)
                const Text(
                  'Kamu',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                _FollowButton(
                  following: user.isFollowing,
                  busy: busy,
                  onTap: onFollowTap,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rail horizontal "Baru dilihat" ala IG — avatar 50 + username di bawah,
/// badge × kecil di pojok untuk hapus per item. Hemat ruang vertikal
/// dibanding list (12 recent = 1 baris rail vs 12 baris list).
class _RecentUserRail extends StatelessWidget {
  final List<FollowUserSummary> users;
  final void Function(FollowUserSummary user) onOpen;
  final void Function(FollowUserSummary user) onRemove;

  const _RecentUserRail({
    required this.users,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: users.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final user = users[index];
          return _RecentUserItem(
            user: user,
            onOpen: () => onOpen(user),
            onRemove: () => onRemove(user),
          );
        },
      ),
    );
  }
}

class _RecentUserItem extends StatelessWidget {
  final FollowUserSummary user;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _RecentUserItem({
    required this.user,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 2,
                    top: 2,
                    child: _Avatar(user: user, size: 50),
                  ),
                  // Badge × — hit-area 22px (badge visual 18) supaya tetap
                  // gampang di-tap tanpa membesarkan visualnya.
                  Positioned(
                    top: -3,
                    right: -3,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onRemove,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: Center(
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: _searchFill,
                              shape: BoxShape.circle,
                              border: Border.all(color: _bg, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFFC4CCD6),
                              size: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              user.displayHandle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFC4CCD6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final FollowUserSummary user;
  final double size;

  const _Avatar({required this.user, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return ProfileAvatar(
      initial: user.initial,
      imageUrl: user.profilePhotoUrl,
      size: size,
      fontSize: 16,
      isOfficial: user.isOfficial,
      plain: true,
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
    // "Mengikuti" = isi abu halus tanpa border (lebih tenang dari outline
    // samar), "Ikuti" = biru brand. Bobot w600, tinggi 30 — ala IG.
    return SizedBox(
      height: 30,
      child: following
          ? FilledButton(
              onPressed: busy ? null : onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                foregroundColor: const Color(0xFFE3E8EF),
                disabledForegroundColor: _muted,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
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
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
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
            Icon(icon, color: Colors.white.withValues(alpha: 0.52), size: 40),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              query == null ? body : '$body\n"$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
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
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          _SkeletonCircle(),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBar(width: 118),
                SizedBox(height: 7),
                _SkeletonBar(width: 170, opacity: 0.09),
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
      width: 44,
      height: 44,
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
