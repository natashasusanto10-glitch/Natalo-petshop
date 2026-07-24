import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_search_entry.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/follow_service.dart';
import '../state/account_scope.dart';
import '../state/follow_override_store.dart';
import '../utils/haptics.dart';
import '../utils/owner_scope.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_avatar.dart';

const _bg = Color(0xFF070B10);
const _searchFill = Color(0xFF242A30);
const _divider = Color(0xFF141A22);
const _muted = Color(0xFF8D96A3);
const _text = Color(0xFFF8FAFC);
const _brandBlue = NataloColors.primary;
// Owner-scoped so recent-searched accounts don't leak across accounts/guest
// on a shared device. Legacy global `feed_user_search_recent_v1` unused.
const _recentStorageBaseKey = 'feed_user_search_recent_v1';
String get _recentStorageKey =>
    OwnerScope.key(_recentStorageBaseKey, accountOwnerId());
const _maxRecentEntries = 12;

typedef SearchHashtagsFn = Future<List<HashtagSuggestion>> Function(String q);
typedef SearchUsersFn = Future<List<FollowUserSummary>> Function(
  String q, {
  int limit,
});

class FeedUserSearchScreen extends StatefulWidget {
  final SearchHashtagsFn? searchHashtagsOverride;
  final SearchUsersFn? searchUsersOverride;

  const FeedUserSearchScreen({
    super.key,
    this.searchHashtagsOverride,
    this.searchUsersOverride,
  });

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
  List<RecentSearchEntry> _recentEntries = const [];
  List<FollowUserSummary> _suggestedUsers = const [];
  List<HashtagSuggestion> _hashtagResults = const [];
  bool _hashtagLoading = false;
  String? _hashtagError;
  String _lastRunHashtagQuery = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
    _loadRecentEntries();
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

  /// Mode hashtag aktif kalau teks (trimmed) diawali '#' ala IG.
  bool get _isHashtagMode => _controller.text.trim().startsWith('#');

  /// Teks setelah '#' — bisa kosong kalau user baru ketik '#' saja.
  String get _hashtagQuery {
    final trimmed = _controller.text.trim();
    return trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  }

  void _onInputChanged() {
    final next = _controller.text.trim();
    if (next == _query) return;
    _debounce?.cancel();
    final hashtagMode = next.startsWith('#');
    final hashtagQuery = hashtagMode ? next.substring(1) : '';
    setState(() {
      _query = next;
      _error = null;
      _loginRequired = false;
      if (hashtagMode) {
        if (hashtagQuery.isEmpty) {
          _lastRunHashtagQuery = '';
          _hashtagResults = const [];
          _hashtagLoading = false;
          _hashtagError = null;
        }
      } else if (next.length < 2) {
        _lastRunQuery = '';
        _items = const [];
        _loading = false;
      }
    });
    if (hashtagMode) {
      if (hashtagQuery.isEmpty) return;
      _debounce = Timer(const Duration(milliseconds: 250), () {
        _runHashtagSearch(hashtagQuery);
      });
      return;
    }
    if (next.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(next);
    });
  }

  Future<void> _runHashtagSearch(String raw) async {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return;
    _lastRunHashtagQuery = q;
    setState(() {
      _hashtagLoading = true;
      _hashtagError = null;
    });
    try {
      final search = widget.searchHashtagsOverride ?? feedService.searchHashtags;
      final items = await search(q);
      if (!mounted || _lastRunHashtagQuery != q || _hashtagNormalizedQuery != q) {
        return;
      }
      setState(() => _hashtagResults = items);
    } catch (_) {
      if (!mounted || _lastRunHashtagQuery != q || _hashtagNormalizedQuery != q) {
        return;
      }
      setState(() {
        _hashtagError = 'Pencarian belum berhasil. Coba lagi.';
        _hashtagResults = const [];
      });
    } finally {
      if (mounted &&
          _lastRunHashtagQuery == q &&
          _hashtagNormalizedQuery == q) {
        setState(() => _hashtagLoading = false);
      }
    }
  }

  String get _hashtagNormalizedQuery => _hashtagQuery.trim().toLowerCase();

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
      final search = widget.searchUsersOverride ?? followService.searchUsers;
      final items = await search(q, limit: 20);
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

  Future<void> _loadRecentEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_recentStorageKey) ?? const <String>[];
    final entries = <RecentSearchEntry>[];
    for (final raw in stored) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final entry =
            RecentSearchEntry.fromJson(Map<String, dynamic>.from(decoded));
        if (!entry.isHashtag && !(entry.user!.canOpenProfile)) continue;
        if (entry.isHashtag && entry.hashtag!.name.isEmpty) continue;
        entries.add(entry);
      } catch (_) {
        // Abaikan entry rusak supaya recent tetap tampil.
      }
    }
    if (!mounted) return;
    setState(() => _recentEntries = entries.take(_maxRecentEntries).toList());
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

  Future<void> _persistRecentEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentStorageKey,
      _recentEntries.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> _rememberRecentUser(FollowUserSummary user) async {
    if (!user.canOpenProfile) return;
    await _rememberEntry(RecentSearchEntry.user(user));
  }

  Future<void> _rememberRecentHashtag(HashtagSuggestion hashtag) async {
    await _rememberEntry(RecentSearchEntry.hashtag(hashtag));
  }

  Future<void> _rememberEntry(RecentSearchEntry entry) async {
    setState(() {
      final next = <RecentSearchEntry>[
        entry,
        ..._recentEntries.where((item) => item.key != entry.key),
      ];
      _recentEntries = next.take(_maxRecentEntries).toList(growable: false);
    });
    await _persistRecentEntries();
  }

  Future<void> _removeRecentEntry(RecentSearchEntry entry) async {
    AppHaptics.tap();
    setState(() {
      _recentEntries = _recentEntries
          .where((item) => item.key != entry.key)
          .toList(growable: false);
    });
    await _persistRecentEntries();
  }

  Future<void> _clearRecentEntries() async {
    AppHaptics.tap();
    setState(() => _recentEntries = const []);
    await _persistRecentEntries();
  }

  Future<void> _openHashtag(HashtagSuggestion hashtag) async {
    AppHaptics.tap();
    unawaited(_rememberRecentHashtag(hashtag));
    await Navigator.pushNamed(context, '/hashtag', arguments: hashtag.name);
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
      _recentEntries = _reconcileRecentFollow(_recentEntries);
      _suggestedUsers = reconcile(_suggestedUsers);
    });
  }

  List<RecentSearchEntry> _reconcileRecentFollow(
    List<RecentSearchEntry> entries,
  ) {
    return entries
        .map((entry) => entry.isHashtag
            ? entry
            : RecentSearchEntry.user(entry.user!.copyWith(
                isFollowing:
                    resolveFollowState(entry.user!.id, entry.user!.isFollowing),
              )))
        .toList(growable: false);
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
    if (_recentEntries.any((e) => !e.isHashtag && e.user!.id == user.id)) {
      unawaited(_persistRecentEntries());
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
      if (_recentEntries.any((e) => !e.isHashtag && e.user!.id == user.id)) {
        unawaited(_persistRecentEntries());
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
      if (_recentEntries.any((e) => !e.isHashtag && e.user!.id == user.id)) {
        unawaited(_persistRecentEntries());
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
    _recentEntries = _replaceUserInEntries(_recentEntries, user);
    _suggestedUsers = _replaceUser(_suggestedUsers, user);
  }

  List<RecentSearchEntry> _replaceUserInEntries(
    List<RecentSearchEntry> entries,
    FollowUserSummary user,
  ) {
    var changed = false;
    final next = entries.map((entry) {
      if (entry.isHashtag || entry.user!.id != user.id) return entry;
      changed = true;
      return RecentSearchEntry.user(user);
    }).toList(growable: false);
    return changed ? next : entries;
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
    if (_isHashtagMode) {
      return _buildHashtagBody();
    }
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

  Widget _buildHashtagBody() {
    if (_hashtagQuery.isEmpty) {
      return const _MessageState(
        icon: Icons.tag_rounded,
        title: 'Cari hashtag',
        body: 'Ketik nama hashtag untuk mencari postingan.',
      );
    }
    if (_hashtagError != null) {
      return _MessageState(
        icon: Icons.search_off_rounded,
        title: 'Pencarian gagal',
        body: _hashtagError!,
        actionLabel: 'Coba lagi',
        onAction: () => _runHashtagSearch(_hashtagQuery),
      );
    }
    if (_hashtagLoading && _hashtagResults.isEmpty) {
      return const _SearchSkeletonList();
    }
    if (!_hashtagLoading && _hashtagResults.isEmpty) {
      return _MessageState(
        icon: Icons.tag_rounded,
        title: 'Hashtag tidak ditemukan',
        body: 'Coba kata kunci lain.',
        query: _hashtagQuery,
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final hashtag in _hashtagResults)
          _HashtagResultTile(
            hashtag: hashtag,
            onTap: () => _openHashtag(hashtag),
          ),
        if (_hashtagLoading)
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

    if (_recentEntries.isNotEmpty) {
      children
        ..add(_SectionHeader(
          title: 'Baru dilihat',
          actionLabel: 'Hapus',
          onAction: () => _clearRecentEntries(),
        ))
        ..addAll(_recentEntries.map(
          (entry) => _RecentEntryTile(
            entry: entry,
            onOpen: () => entry.isHashtag
                ? _openHashtag(entry.hashtag!)
                : _openProfile(entry.user!),
            onRemove: () => _removeRecentEntry(entry),
          ),
        ))
        ..add(const Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Divider(height: 1, thickness: 0.5, color: _divider),
        ));
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
                  hintText: 'Cari akun atau #hashtag',
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

/// Baris "Baru dilihat" campur akun+hashtag ala IG — daftar vertikal,
/// tombol X per-baris untuk hapus satu, "Hapus" di header untuk semua.
class _RecentEntryTile extends StatelessWidget {
  final RecentSearchEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _RecentEntryTile({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final title = entry.isHashtag
        ? '#${entry.hashtag!.name}'
        : (entry.user!.username ?? entry.user!.name);
    final subtitle = entry.isHashtag
        ? '${entry.hashtag!.postCount} postingan'
        : (entry.user!.name.isNotEmpty &&
                entry.user!.name != entry.user!.username
            ? entry.user!.name
            : '${_formatCount(entry.user!.followersCount)} pengikut');
    return InkWell(
      onTap: onOpen,
      splashColor: Colors.white.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Row(
          children: [
            if (entry.isHashtag)
              const _HashtagCircle(size: 44)
            else
              _Avatar(user: entry.user!),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
            const SizedBox(width: 8),
            // Tombol X per-baris — hit target 44dp (konvensi proyek).
            Semantics(
              button: true,
              label: 'Hapus dari riwayat',
              child: GestureDetector(
                key: ValueKey('recent-remove-${entry.key}'),
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.close_rounded,
                    color: _muted,
                    size: 18,
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

/// Baris hasil pencarian hashtag ala IG — polos, TANPA tombol X (bukan
/// riwayat). Layout senada _RecentEntryTile varian hashtag.
class _HashtagResultTile extends StatelessWidget {
  final HashtagSuggestion hashtag;
  final VoidCallback onTap;

  const _HashtagResultTile({
    required this.hashtag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.06),
      highlightColor: Colors.white.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Row(
          children: [
            const _HashtagCircle(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${hashtag.name}',
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
                    '${hashtag.postCount} postingan',
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
          ],
        ),
      ),
    );
  }
}

/// Lingkaran ikon '#' — leading entry hashtag, gaya senada leading
/// HashtagSuggestionsPanel (widgets/hashtag_picker.dart) & screenshot IG.
class _HashtagCircle extends StatelessWidget {
  final double size;
  const _HashtagCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _searchFill,
        shape: BoxShape.circle,
        border: Border.all(color: _divider, width: 1),
      ),
      child: const Center(
        child: Icon(Icons.tag_rounded, color: _text, size: 20),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final FollowUserSummary user;
  static const double size = 44;

  const _Avatar({required this.user});

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
