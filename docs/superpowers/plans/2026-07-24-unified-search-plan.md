# Unified Search (Akun + Hashtag) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Satu kotak search di `FeedUserSearchScreen`: teks biasa → hasil akun (perilaku existing), prefix `#` → hasil hashtag; recent campur akun+hashtag sebagai daftar vertikal ala IG.

**Architecture:** Flutter-only (TIDAK ADA perubahan backend — reuse `followService.searchUsers` + `feedService.searchHashtags`). Model union `RecentSearchEntry` di file baru menggantikan `List<FollowUserSummary>` untuk storage recent (key & format lama backward-compatible). `_RecentUserRail` (horizontal) diganti `_RecentEntryList` (vertikal). Mode hashtag = branch render + branch debounce-search dalam state screen yang sama.

**Tech Stack:** Flutter, SharedPreferences (storage recent, owner-scoped), flutter_test.

## Global Constraints

- Search Beranda/Produk (`home_screen.dart`, `products_screen.dart`) TIDAK disentuh sama sekali (instruksi proyek).
- TIDAK ADA perubahan backend/endpoint; TIDAK ADA kelas argumen route baru — buka halaman hashtag persis `Navigator.pushNamed(context, '/hashtag', arguments: name)` dengan `name` String polos tanpa `#` (lihat `main.dart:426-429`).
- Storage key recent TETAP `feed_user_search_recent_v1` (owner-scoped via `OwnerScope.key`); entry lama tanpa field `type` WAJIB tetap ter-parse sebagai akun (backward compat, tanpa migrasi).
- Maks recent 12 entry campur; dedupe by key (`user:<id>` / `hashtag:<name>`); terbaru di atas.
- Recent = daftar VERTIKAL (baris: leading avatar/ikon `#` 44px + title + subtitle + tombol X per-baris), TANPA "See all". Header pakai `_SectionHeader` existing (title `'Baru dilihat'`, action `'Hapus'`).
- Subtitle hashtag: `'${postCount} postingan'`. Title hashtag: `'#${name}'`.
- Mode hashtag aktif ketika input (setelah trim) diawali `#`. Query `#` doang → empty-state hashtag ("Cari hashtag" / "Ketik nama hashtag setelah #."), BUKAN suggested users, BUKAN error.
- Debounce 250ms existing dipertahankan untuk kedua mode.
- Suggested users (kotak kosong) tidak berubah; tidak ada suggested hashtags.
- Tiap tap interaktif baru pakai `AppHaptics.tap()`. Semua copy bahasa Indonesia.
- Style konsisten dengan konstanta file (`_bg`, `_searchFill`, `_muted`, `_text`); lingkaran ikon `#` mengikuti gaya leading `HashtagSuggestionsPanel` (`widgets/hashtag_picker.dart`).

---

### Task 1: Model `RecentSearchEntry` (file baru + unit test)

**Files:**
- Create: `flutter_app/lib/models/recent_search_entry.dart`
- Test: `flutter_app/test/models/recent_search_entry_test.dart`

**Interfaces:**
- Consumes: `FollowUserSummary` (`services/follow_service.dart`, punya `toJson`/`fromJson`/`id`), `HashtagSuggestion` (`services/feed_service.dart`, fields `name`+`postCount`).
- Produces: `RecentSearchEntry` dengan `RecentSearchEntry.user(FollowUserSummary)`, `RecentSearchEntry.hashtag(HashtagSuggestion)`, getter `isHashtag`, `key`, `toJson()`, `factory RecentSearchEntry.fromJson(Map<String, dynamic>)` — dipakai Task 2.

- [ ] **Step 1: Tulis failing test** — `flutter_app/test/models/recent_search_entry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:toko_pwa_app/models/recent_search_entry.dart';
import 'package:toko_pwa_app/services/feed_service.dart';
import 'package:toko_pwa_app/services/follow_service.dart';

// PENTING: cek nama package import di test existing (mis.
// test/services/feed_service_hashtag_test.dart) dan SAMAKAN prefiksnya —
// 'toko_pwa_app' di sini tebakan; pakai yang asli.

void main() {
  test('hashtag entry: toJson bawa type/name/postCount, round-trip utuh', () {
    const entry = RecentSearchEntry.hashtag(
      HashtagSuggestion(name: 'kucing', postCount: 12),
    );
    final json = entry.toJson();
    expect(json['type'], 'hashtag');
    expect(json['name'], 'kucing');
    expect(json['postCount'], 12);
    final back = RecentSearchEntry.fromJson(json);
    expect(back.isHashtag, isTrue);
    expect(back.hashtag!.name, 'kucing');
    expect(back.hashtag!.postCount, 12);
    expect(back.key, 'hashtag:kucing');
  });

  test('user entry: toJson berisi field user + type=user, key=user:<id>', () {
    const user = FollowUserSummary(
      id: 'u1',
      name: 'Rani',
      username: 'rani_ap',
    );
    const entry = RecentSearchEntry.user(user);
    final json = entry.toJson();
    expect(json['type'], 'user');
    expect(json['id'], 'u1');
    final back = RecentSearchEntry.fromJson(json);
    expect(back.isHashtag, isFalse);
    expect(back.user!.id, 'u1');
    expect(back.key, 'user:u1');
  });

  test('backward compat: JSON lama tanpa field type ter-parse sebagai user', () {
    // Format storage lama = FollowUserSummary.toJson() murni.
    const user = FollowUserSummary(id: 'u2', name: 'Budi', username: 'budi');
    final legacyJson = user.toJson(); // tidak punya 'type'
    final back = RecentSearchEntry.fromJson(legacyJson);
    expect(back.isHashtag, isFalse);
    expect(back.user!.id, 'u2');
  });
}
```

(Kalau konstruktor `FollowUserSummary` butuh field wajib lain, isi nilai default minimal sesuai definisinya di `follow_service.dart:51-80` — jangan ubah kelasnya.)

- [ ] **Step 2: Run, verify FAIL** — dari `flutter_app/`: `flutter test test/models/recent_search_entry_test.dart` → FAIL compile (file model belum ada).

- [ ] **Step 3: Implementasi** — `flutter_app/lib/models/recent_search_entry.dart`:

```dart
import '../services/feed_service.dart';
import '../services/follow_service.dart';

/// Satu entry riwayat pencarian unified search — akun ATAU hashtag,
/// tidak pernah dua-duanya (union sederhana, spec unified-search §Model).
///
/// Serialisasi ke SharedPreferences pakai field diskriminator `type`
/// ('user' | 'hashtag'). Entry storage LAMA (murni FollowUserSummary.toJson,
/// tanpa `type`) WAJIB tetap ter-parse sebagai user — backward compat tanpa
/// migrasi.
class RecentSearchEntry {
  final FollowUserSummary? user;
  final HashtagSuggestion? hashtag;

  const RecentSearchEntry.user(FollowUserSummary this.user) : hashtag = null;
  const RecentSearchEntry.hashtag(HashtagSuggestion this.hashtag)
      : user = null;

  bool get isHashtag => hashtag != null;

  /// Identity untuk dedupe recent.
  String get key => isHashtag ? 'hashtag:${hashtag!.name}' : 'user:${user!.id}';

  Map<String, dynamic> toJson() => isHashtag
      ? {
          'type': 'hashtag',
          'name': hashtag!.name,
          'postCount': hashtag!.postCount,
        }
      : {'type': 'user', ...user!.toJson()};

  factory RecentSearchEntry.fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'hashtag') {
      return RecentSearchEntry.hashtag(
        HashtagSuggestion(
          name: (json['name'] as String?) ?? '',
          postCount: (json['postCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    // 'user' eksplisit ATAU legacy tanpa 'type' → user.
    return RecentSearchEntry.user(FollowUserSummary.fromJson(json));
  }
}
```

(Kalau `HashtagSuggestion` bukan `const`-constructible, sesuaikan test — hapus `const` di sana; JANGAN ubah `HashtagSuggestion`.)

- [ ] **Step 4: Run, verify PASS** — `flutter test test/models/recent_search_entry_test.dart` → 3 pass. `flutter analyze lib/models/recent_search_entry.dart` → bersih.

- [ ] **Step 5: Commit** — `git add flutter_app/lib/models/recent_search_entry.dart flutter_app/test/models/recent_search_entry_test.dart && git commit -m "feat(app): model RecentSearchEntry utk unified search (akun/hashtag)"`

---

### Task 2: Recent campur vertikal di FeedUserSearchScreen

**Files:**
- Modify: `flutter_app/lib/screens/feed_user_search_screen.dart` (state `_recentUsers` → `_recentEntries`; `_RecentUserRail`+`_RecentUserItem` dihapus, diganti `_RecentEntryList`)
- Test: `flutter_app/test/screens/feed_user_search_recent_mixed_test.dart` (create)

**Interfaces:**
- Consumes: `RecentSearchEntry` (Task 1).
- Produces: method `_rememberRecentHashtag(HashtagSuggestion)` — dipakai Task 3. State `List<RecentSearchEntry> _recentEntries`.

- [ ] **Step 1: Failing widget test** — `flutter_app/test/screens/feed_user_search_recent_mixed_test.dart`. Pola setup: mock `SharedPreferences.setMockInitialValues`, seed storage dengan 1 user + 1 hashtag entry, pump `FeedUserSearchScreen`, bounded pump-loop (JANGAN `pumpAndSettle` — gotcha shimmer proyek ini):

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toko_pwa_app/screens/feed_user_search_screen.dart';

// Samakan prefix package dgn test existing. Cek juga cara test existing
// (mis. test yang menyentuh screen dgn network) menetralkan apiClient —
// ikuti pola file test screen terdekat.

Future<void> pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('recent campur: user & hashtag render + dismiss per-baris',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      // Key TANPA owner-scope prefix kalau accountOwnerId() default guest —
      // baca OwnerScope.key + accountOwnerId utk bentuk key persis, dan
      // set nilai mock key yang sama dgn yang dipakai screen saat test run.
      'feed_user_search_recent_v1': <String>[
        jsonEncode({
          'type': 'user',
          'id': 'u1',
          'name': 'Rani',
          'username': 'rani_ap',
        }),
        jsonEncode({'type': 'hashtag', 'name': 'kucing', 'postCount': 3}),
      ],
    });
    await tester.pumpWidget(const MaterialApp(home: FeedUserSearchScreen()));
    await pumpBounded(tester);

    expect(find.text('rani_ap'), findsOneWidget);
    expect(find.text('#kucing'), findsOneWidget);
    expect(find.text('3 postingan'), findsOneWidget);

    // Dismiss entry hashtag via tombol X-nya; user tetap ada.
    await tester.tap(find.byKey(const ValueKey('recent-remove-hashtag:kucing')));
    await pumpBounded(tester);
    expect(find.text('#kucing'), findsNothing);
    expect(find.text('rani_ap'), findsOneWidget);
  });

  testWidgets('backward compat: entry lama tanpa type render sebagai user',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'feed_user_search_recent_v1': <String>[
        jsonEncode({'id': 'u9', 'name': 'Lama', 'username': 'akunlama'}),
      ],
    });
    await tester.pumpWidget(const MaterialApp(home: FeedUserSearchScreen()));
    await pumpBounded(tester);
    expect(find.text('akunlama'), findsOneWidget);
  });
}
```

Catatan storage-key di test: `_recentStorageKey` = `OwnerScope.key('feed_user_search_recent_v1', accountOwnerId())`. Baca `utils/owner_scope.dart` + `state/account_scope.dart` untuk tahu bentuk key saat guest (kemungkinan ada prefix/suffix owner) dan mock key PERSIS itu — kalau tidak match, screen baca list kosong dan test gagal misterius.

- [ ] **Step 2: Run, verify FAIL** — `flutter test test/screens/feed_user_search_recent_mixed_test.dart` → gagal (screen masih render rail lama, `#kucing` tidak ada, ValueKey belum ada).

- [ ] **Step 3: Implementasi di `feed_user_search_screen.dart`:**

1. Import `../models/recent_search_entry.dart` (dan `feed_service.dart` untuk `HashtagSuggestion`).
2. Rename konstanta `_maxRecentUsers` → `_maxRecentEntries` (nilai tetap 12).
3. State: `List<FollowUserSummary> _recentUsers` → `List<RecentSearchEntry> _recentEntries = const [];`
4. `_loadRecentUsers()` → `_loadRecentEntries()`: decode tiap raw JSON ke `RecentSearchEntry.fromJson`; untuk entry user pertahankan filter `canOpenProfile`:

```dart
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
```

5. `_persistRecentUsers()` → `_persistRecentEntries()` (encode `entry.toJson()`).
6. `_rememberRecentUser(user)` → bungkus jadi entry + dedupe by `.key`:

```dart
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
```

`_clearRecentUsers()` → `_clearRecentEntries()` (isi sama, list kosong + persist).
7. Follow-state reconcile (`_openProfile` bagian `reconcile` + `_replaceUserEverywhere`): terap hanya ke entry user —

```dart
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
```

dan di `_replaceUser`-equivalent untuk recent: ganti hanya entry user dengan id sama. Panggilan `_recentUsers.any((item) => item.id == user.id)` di `_toggleFollow` → `_recentEntries.any((e) => !e.isHashtag && e.user!.id == user.id)`.
8. Render default body: blok `_RecentUserRail` diganti list vertikal:

```dart
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
```

(`_openHashtag` didefinisikan di Task 3; untuk Task 2 sementara stub method privat yang langsung `Navigator.pushNamed(context, '/hashtag', arguments: hashtag.name)` setelah `AppHaptics.tap()` + `unawaited(_rememberRecentHashtag(hashtag))` — Task 3 tinggal reuse.)
9. Hapus kelas `_RecentUserRail` + `_RecentUserItem`; tambah `_RecentEntryTile`:

```dart
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
```

(Cek dulu leading persis `HashtagSuggestionsPanel` di `hashtag_picker.dart` — kalau di sana pakai `Icons.tag` / karakter teks `#`, samakan pilihan ikonnya.)

- [ ] **Step 4: Run, verify PASS** — kedua test file (`recent_mixed` + model) hijau; `flutter analyze lib/screens/feed_user_search_screen.dart` → tidak ada issue baru.

- [ ] **Step 5: Commit** — `git add -A flutter_app/lib/screens/feed_user_search_screen.dart flutter_app/lib/models/recent_search_entry.dart flutter_app/test/screens/feed_user_search_recent_mixed_test.dart && git commit -m "feat(app): recent unified search campur akun+hashtag, daftar vertikal ala IG"`

---

### Task 3: Mode hashtag (prefix `#`) + hasil + navigasi

**Files:**
- Modify: `flutter_app/lib/screens/feed_user_search_screen.dart`
- Test: `flutter_app/test/screens/feed_user_search_hashtag_mode_test.dart` (create)

**Interfaces:**
- Consumes: `feedService.searchHashtags(String) → Future<List<HashtagSuggestion>>` (existing), `_rememberRecentHashtag` (Task 2).
- Produces: perilaku final unified search.

- [ ] **Step 1: Failing widget test** — `flutter_app/test/screens/feed_user_search_hashtag_mode_test.dart`. Injeksi fetcher: screen memanggil `feedService.searchHashtags` global — supaya bisa dites tanpa network, tambahkan parameter opsional constructor (pola injectable yang sama dengan `HashtagPickerController.searchFn` dan `HashtagScreen.fetcher`):

```dart
// Di FeedUserSearchScreen:
final Future<List<HashtagSuggestion>> Function(String q)? hashtagSearchFn;
final Future<List<FollowUserSummary>> Function(String q)? userSearchFn;
const FeedUserSearchScreen({super.key, this.hashtagSearchFn, this.userSearchFn});
// null → produksi: feedService.searchHashtags / followService.searchUsers(q, limit: 20)
```

Test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toko_pwa_app/screens/feed_user_search_screen.dart';
import 'package:toko_pwa_app/services/feed_service.dart';

Future<void> pumpBounded(WidgetTester tester,
    [Duration step = const Duration(milliseconds: 50)]) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(step);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('#query → hasil hashtag tampil, bukan hasil akun',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedUserSearchScreen(
        hashtagSearchFn: (q) async => [
          HashtagSuggestion(name: 'kucing', postCount: 42),
        ],
        userSearchFn: (q) async => throw StateError('tidak boleh dipanggil'),
      ),
    ));
    await pumpBounded(tester);
    await tester.enterText(find.byType(TextField), '#ku');
    await pumpBounded(tester); // lewati debounce 250ms
    expect(find.text('#kucing'), findsOneWidget);
    expect(find.text('42 postingan'), findsOneWidget);
  });

  testWidgets('tap hasil hashtag → push /hashtag dgn arg nama polos',
      (tester) async {
    String? pushedRoute;
    Object? pushedArgs;
    await tester.pumpWidget(MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name == '/hashtag') {
          pushedRoute = settings.name;
          pushedArgs = settings.arguments;
          return MaterialPageRoute(builder: (_) => const SizedBox());
        }
        return null;
      },
      home: FeedUserSearchScreen(
        hashtagSearchFn: (q) async => [
          HashtagSuggestion(name: 'kucing', postCount: 42),
        ],
      ),
    ));
    await pumpBounded(tester);
    await tester.enterText(find.byType(TextField), '#ku');
    await pumpBounded(tester);
    await tester.tap(find.text('#kucing'));
    await pumpBounded(tester);
    expect(pushedRoute, '/hashtag');
    expect(pushedArgs, 'kucing');
  });

  testWidgets('"#" doang → empty-state hashtag, bukan suggested users',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedUserSearchScreen(
        hashtagSearchFn: (q) async => const [],
      ),
    ));
    await pumpBounded(tester);
    await tester.enterText(find.byType(TextField), '#');
    await pumpBounded(tester);
    expect(find.text('Cari hashtag'), findsOneWidget);
    expect(find.text('Akun yang mungkin kamu kenal'), findsNothing);
  });
}
```

- [ ] **Step 2: Run, verify FAIL** — mode belum ada.

- [ ] **Step 3: Implementasi di `feed_user_search_screen.dart`:**

1. Constructor + 2 field injectable seperti di Step 1 (default null → produksi).
2. State tambahan: `List<HashtagSuggestion> _hashtagResults = const [];`
3. Getter mode:

```dart
bool get _isHashtagMode => _controller.text.trim().startsWith('#');
String get _hashtagQuery {
  final t = _controller.text.trim();
  return t.startsWith('#') ? t.substring(1).trim().toLowerCase() : '';
}
```

4. `_onInputChanged`: threshold jalan-search per mode — mode akun tetap `< 2`; mode hashtag jalan saat `_hashtagQuery.isNotEmpty` (1 huruf sudah berarti — prefix match server). Reset `_hashtagResults`/`_items` saat mode berganti:

```dart
void _onInputChanged() {
  final next = _controller.text.trim();
  if (next == _query) return;
  _debounce?.cancel();
  final hashtagMode = next.startsWith('#');
  final effectiveLen = hashtagMode ? next.length - 1 : next.length;
  setState(() {
    _query = next;
    _error = null;
    _loginRequired = false;
    if (hashtagMode) _items = const [];
    if (!hashtagMode) _hashtagResults = const [];
    if (effectiveLen < (hashtagMode ? 1 : 2)) {
      _lastRunQuery = '';
      _items = const [];
      _hashtagResults = const [];
      _loading = false;
    }
  });
  if (effectiveLen < (hashtagMode ? 1 : 2)) return;
  _debounce = Timer(const Duration(milliseconds: 250), () {
    if (hashtagMode) {
      _runHashtagSearch(_hashtagQuery);
    } else {
      _runSearch(next);
    }
  });
}
```

5. `_runHashtagSearch` (mirror `_runSearch`, guard stale-query sama):

```dart
Future<void> _runHashtagSearch(String q) async {
  if (q.isEmpty) return;
  _lastRunQuery = '#$q';
  setState(() {
    _loading = true;
    _error = null;
    _loginRequired = false;
  });
  try {
    final search = widget.hashtagSearchFn ?? feedService.searchHashtags;
    final results = await search(q);
    if (!mounted || _lastRunQuery != '#$q' || _hashtagQuery != q) return;
    setState(() => _hashtagResults = results);
  } catch (error) {
    if (!mounted || _lastRunQuery != '#$q' || _hashtagQuery != q) return;
    if (error is ApiException && error.statusCode == 401) {
      setState(() {
        _loginRequired = true;
        _hashtagResults = const [];
      });
    } else {
      setState(() {
        _error = 'Pencarian belum berhasil. Coba lagi.';
        _hashtagResults = const [];
      });
    }
  } finally {
    if (mounted && _lastRunQuery == '#$q') {
      setState(() => _loading = false);
    }
  }
}
```

Di `_runSearch` existing: ganti `followService.searchUsers(q, limit: 20)` jadi `final search = widget.userSearchFn ?? ((qq) => followService.searchUsers(qq, limit: 20)); final items = await search(q);` (behavior produksi identik).
6. `_buildBody`: branch mode hashtag SEBELUM cek `< 2` existing:

```dart
Widget _buildBody() {
  if (_isHashtagMode) {
    if (_hashtagQuery.isEmpty) {
      return const _MessageState(
        icon: Icons.tag_rounded,
        title: 'Cari hashtag',
        body: 'Ketik nama hashtag setelah #.',
      );
    }
    if (_loginRequired) {
      return _MessageState(
        icon: Icons.lock_outline_rounded,
        title: 'Login untuk cari hashtag',
        body: 'Masuk dulu supaya bisa menjelajah hashtag Natalo.',
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
        onAction: () => _runHashtagSearch(_hashtagQuery),
      );
    }
    if (_loading && _hashtagResults.isEmpty) {
      return const _SearchSkeletonList();
    }
    if (!_loading && _hashtagResults.isEmpty) {
      return _MessageState(
        icon: Icons.tag_rounded,
        title: 'Hashtag tidak ditemukan',
        body: 'Coba nama hashtag lain.',
        query: _query,
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final tag in _hashtagResults)
          _HashtagResultTile(
            hashtag: tag,
            onTap: () => _openHashtag(tag),
          ),
      ],
    );
  }
  // ... sisanya body existing (mode akun) TIDAK berubah.
```

7. `_openHashtag` (kalau Task 2 sudah bikin stub, lengkapi):

```dart
Future<void> _openHashtag(HashtagSuggestion hashtag) async {
  if (hashtag.name.isEmpty) return;
  AppHaptics.tap();
  unawaited(_rememberRecentHashtag(hashtag));
  await Navigator.pushNamed(context, '/hashtag', arguments: hashtag.name);
}
```

8. `_HashtagResultTile` — sama persis layout `_RecentEntryTile` versi hashtag TANPA tombol X:

```dart
class _HashtagResultTile extends StatelessWidget {
  final HashtagSuggestion hashtag;
  final VoidCallback onTap;

  const _HashtagResultTile({required this.hashtag, required this.onTap});

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
```

9. Hint kotak search: `'Cari akun'` → `'Cari akun atau #hashtag'`.

- [ ] **Step 4: Run, verify PASS** — ketiga test file hijau (`hashtag_mode`, `recent_mixed`, model); `flutter analyze lib/screens/feed_user_search_screen.dart` bersih.

- [ ] **Step 5: Commit** — `git add -A flutter_app/lib/screens/feed_user_search_screen.dart flutter_app/test/screens/feed_user_search_hashtag_mode_test.dart && git commit -m "feat(app): mode hashtag di unified search (prefix #) + navigasi /hashtag"`

---

### Task 4: Regresi penuh

**Files:** tidak ada perubahan kode (kecuali fix regresi yang ditemukan).

- [ ] **Step 1:** Dari `flutter_app/`: `flutter analyze` → bandingkan jumlah issue dengan baseline sebelum branch (tidak boleh bertambah).
- [ ] **Step 2:** `flutter test` penuh → tidak ada failure BARU vs baseline branch (failure pre-existing terdokumentasi boleh, sebutkan di report).
- [ ] **Step 3:** Kalau ada regresi dari kerjaan ini: fix, ulangi, commit terpisah.
- [ ] **Step 4: Commit** (kalau ada perubahan) — `git commit -m "test: regresi penuh unified search"`
