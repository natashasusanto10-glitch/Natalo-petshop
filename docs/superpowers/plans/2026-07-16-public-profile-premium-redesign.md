# Public Profile Premium Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mengimplementasikan public profile official dan regular sesuai mockup final: header compact, mutual follower official, Pesan ke NLCATTER, tiga pill netral, dan transisi glass right-to-left yang smooth tanpa mengubah profil sendiri atau grid.

**Architecture:** Endpoint public profile memperoleh blok mutual follower optional yang backward-compatible. Flutter memisahkan expanded identity, public tab presentation, scroll motion, dan glass chrome menjadi unit terfokus. `NestedScrollView` tetap memiliki tab/content state, sedangkan overlay hanya mendengarkan scroll dan menggambar toolbar/tab di atas grid dengan satu blur layer.

**Tech Stack:** Next.js route handler, Prisma 6.19, TypeScript `node:test`, Flutter/Dart, Material 3, `TabController`, `NestedScrollView`, `BackdropFilter`, Flutter widget/golden tests.

## Global Constraints

- Source of truth: `docs/superpowers/specs/2026-07-16-public-profile-premium-redesign-design.md`.
- Gunakan worktree terisolasi melalui `superpowers:using-git-worktrees` sebelum menyentuh source karena working tree utama memiliki perubahan user yang tidak terkait.
- Jangan mengubah atau stage `.superpowers/sdd/task-1-report.md`, `.superpowers/sdd/task-3-report.md`, `docs/superpowers/specs/2026-07-16-feed-profile-race-equivalence-audit-design.md`, `flutter_app/lib/widgets/feed_comment_sheet.dart`, atau untracked workspace artifacts.
- Official expanded tetap memakai `NataloColors.heroGradientV`; regular expanded memakai `colorScheme.surface`.
- Tab public tidak memakai biru, shared capsule, atau underline ketika collapsed.
- Collapsed chrome memakai satu blur layer; dilarang memakai `BackdropFilter` per pill.
- Grid tetap tiga kolom, rasio 4:5, edge-to-edge, gap 1 logical pixel.
- `MemberScreen`, bottom navigation profil sendiri, playback, prewarm, origin handoff, pagination, dan follow mutation tidak boleh berubah.
- `Pesan` hanya untuk official non-owner ketika `chatStore.chatEnabled`; route tujuan harus `/chat` tanpa endpoint/room baru.
- Mutual followers hanya memakai data nyata; kosong berarti widget dan spacing tidak dirender.
- Tidak ada migrasi Prisma atau dependency baru.
- Target bebas overflow: lebar 320/360/393/430, text scale 1.0/1.3/2.0, light/dark.
- Visual target compact boleh 36-40 px, tetapi hit target dan semantics minimum 44 px.
- Normal motion scroll-driven dan reversible; reduced motion linear tanpa animated blur.

## File Map

### Backend

- Create `lib/social/profile-mutual-followers.ts`: query intersection follow, privacy branding, fallback kosong.
- Modify `app/api/u/[username]/route.ts`: panggil helper dan serialisasikan blok `mutualFollowers`.
- Create `tests/public-profile-mutual-followers.test.ts`: gating, query shape, ordering, privacy, dan fallback.

### Flutter data dan UI

- Modify `flutter_app/lib/models/public_profile.dart`: model preview dan summary mutual.
- Modify `flutter_app/lib/services/profile_service.dart`: parsing blok top-level mutual.
- Modify `flutter_app/lib/screens/public_profile_screen.dart`: viewer reset, action wiring, scroll space, overlay.
- Create `flutter_app/lib/widgets/public_profile_expanded_header.dart`: official/regular compact identity dan action matrix.
- Create `flutter_app/lib/widgets/public_profile_mutual_followers_row.dart`: avatar overlap dan copy `Diikuti oleh`.
- Modify `flutter_app/lib/widgets/public_profile_header_motion.dart`: staged scroll values dan reduced motion.
- Create `flutter_app/lib/widgets/public_profile_content_tab_bar.dart`: icon-only expanded dan tiga pill individual collapsed.
- Create `flutter_app/lib/widgets/public_profile_chrome_overlay.dart`: toolbar, satu glass layer, compact identity, dan tab travel.
- Delete `flutter_app/lib/widgets/public_profile_collapsing_header.dart` setelah screen berpindah ke overlay.

### Tests

- Create `flutter_app/test/models/public_profile_test.dart`.
- Modify `flutter_app/test/screens/public_profile_sync_test.dart`.
- Create `flutter_app/test/widgets/public_profile_expanded_header_test.dart`.
- Modify `flutter_app/test/widgets/public_profile_header_motion_test.dart`.
- Create `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart`.
- Create `flutter_app/test/widgets/public_profile_chrome_overlay_test.dart`.
- Delete `flutter_app/test/widgets/public_profile_collapsing_header_test.dart` setelah coverage dipindahkan.
- Modify `flutter_app/test/screens/public_profile_screen_test.dart`.
- Create `flutter_app/test/screens/member_profile_navigation_regression_test.dart`.
- Create `flutter_app/test/golden/public_profile_premium_test.dart` dan empat PNG baseline.

---

### Task 1: Backend mutual follower contract

**Files:**
- Create: `lib/social/profile-mutual-followers.ts`
- Modify: `app/api/u/[username]/route.ts:22-38,157-242,265-285`
- Create: `tests/public-profile-mutual-followers.test.ts`

**Interfaces:**
- Produces `loadOfficialMutualFollowers(input, dependencies?) -> Promise<PublicMutualFollowerSummary>`.
- Produces response field `mutualFollowers: { items, totalCount }`.
- No database schema change.

- [ ] **Step 1: Write failing helper tests**

Create `tests/public-profile-mutual-followers.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMutualFollowerWhere,
  loadOfficialMutualFollowers,
  type MutualFollowerDependencies,
} from "@/lib/social/profile-mutual-followers";

test("mutual query intersects viewer following with target followers", () => {
  assert.deepEqual(buildMutualFollowerWhere("viewer-1", "official-1"), {
    followingId: "official-1",
    follower: {
      followers: {
        some: { followerId: "viewer-1" },
      },
    },
  });
});

test("mutuals are gated to authenticated official non-owner viewers", async () => {
  let calls = 0;
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => {
      calls += 1;
      return [];
    },
    count: async () => {
      calls += 1;
      return 0;
    },
  };

  for (const input of [
    { viewerUserId: null, targetUserId: "official-1", isOfficial: true, isOwner: false },
    { viewerUserId: "viewer-1", targetUserId: "user-1", isOfficial: false, isOwner: false },
    { viewerUserId: "official-1", targetUserId: "official-1", isOfficial: true, isOwner: true },
  ]) {
    assert.deepEqual(await loadOfficialMutualFollowers(input, dependencies), {
      items: [],
      totalCount: 0,
    });
  }
  assert.equal(calls, 0);
});

test("mutuals brandify admin previews and preserve total count", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => [
      {
        follower: {
          id: "admin-2",
          name: "Private Admin Name",
          username: "admin-two",
          profilePhotoUrl: "https://cdn.example/admin.jpg",
          role: "ADMIN",
        },
      },
      {
        follower: {
          id: "user-2",
          name: "Mona",
          username: "mona",
          profilePhotoUrl: "https://cdn.example/mona.jpg",
          role: "CUSTOMER",
        },
      },
    ],
    count: async () => 7,
  };

  const result = await loadOfficialMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOfficial: true,
      isOwner: false,
    },
    dependencies,
  );

  assert.equal(result.totalCount, 7);
  assert.deepEqual(result.items[0], {
    id: "admin-2",
    name: "Natalo Petshop Official",
    username: "admin-two",
    profilePhotoUrl: null,
    isOfficial: true,
  });
  assert.equal(result.items[1]?.name, "Mona");
});

test("optional mutual failure returns empty summary", async () => {
  const dependencies: MutualFollowerDependencies = {
    findMany: async () => {
      throw new Error("database unavailable");
    },
    count: async () => 4,
  };
  const result = await loadOfficialMutualFollowers(
    {
      viewerUserId: "viewer-1",
      targetUserId: "official-1",
      isOfficial: true,
      isOwner: false,
    },
    dependencies,
  );
  assert.deepEqual(result, { items: [], totalCount: 0 });
});
```

- [ ] **Step 2: Run the focused backend test and confirm RED**

Run:

```powershell
npx tsx --test tests/public-profile-mutual-followers.test.ts
```

Expected: FAIL with module-not-found for `lib/social/profile-mutual-followers.ts`.

- [ ] **Step 3: Implement the helper with injectable dependencies**

Create `lib/social/profile-mutual-followers.ts`:

```ts
import type { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  brandDisplayName,
  brandPhotoUrl,
  isAdminRole,
} from "@/lib/social/brand-user";

export type PublicMutualFollower = {
  id: string;
  name: string;
  username: string | null;
  profilePhotoUrl: string | null;
  isOfficial: boolean;
};

export type PublicMutualFollowerSummary = {
  items: PublicMutualFollower[];
  totalCount: number;
};

type MutualFollowerRow = {
  follower: {
    id: string;
    name: string | null;
    username: string | null;
    profilePhotoUrl: string | null;
    role: string | null;
  };
};

export type MutualFollowerDependencies = {
  findMany: (where: Prisma.UserFollowWhereInput) => Promise<MutualFollowerRow[]>;
  count: (where: Prisma.UserFollowWhereInput) => Promise<number>;
};

export type LoadOfficialMutualFollowersInput = {
  viewerUserId: string | null;
  targetUserId: string;
  isOfficial: boolean;
  isOwner: boolean;
};

const emptySummary = (): PublicMutualFollowerSummary => ({
  items: [],
  totalCount: 0,
});

export function buildMutualFollowerWhere(
  viewerUserId: string,
  targetUserId: string,
): Prisma.UserFollowWhereInput {
  return {
    followingId: targetUserId,
    follower: {
      followers: {
        some: { followerId: viewerUserId },
      },
    },
  };
}

const defaultDependencies: MutualFollowerDependencies = {
  findMany: (where) =>
    prisma.userFollow.findMany({
      where,
      orderBy: [{ createdAt: "desc" }, { id: "asc" }],
      take: 3,
      select: {
        follower: {
          select: {
            id: true,
            name: true,
            username: true,
            profilePhotoUrl: true,
            role: true,
          },
        },
      },
    }),
  count: (where) => prisma.userFollow.count({ where }),
};

export async function loadOfficialMutualFollowers(
  input: LoadOfficialMutualFollowersInput,
  dependencies: MutualFollowerDependencies = defaultDependencies,
): Promise<PublicMutualFollowerSummary> {
  if (!input.viewerUserId || !input.isOfficial || input.isOwner) {
    return emptySummary();
  }
  const where = buildMutualFollowerWhere(
    input.viewerUserId,
    input.targetUserId,
  );
  try {
    const [rows, totalCount] = await Promise.all([
      dependencies.findMany(where),
      dependencies.count(where),
    ]);
    return {
      items: rows.map(({ follower }) => ({
        id: follower.id,
        name: brandDisplayName(follower.role, follower.name),
        username: follower.username,
        profilePhotoUrl: brandPhotoUrl(
          follower.role,
          follower.profilePhotoUrl,
        ),
        isOfficial: isAdminRole(follower.role),
      })),
      totalCount,
    };
  } catch {
    return emptySummary();
  }
}
```

- [ ] **Step 4: Wire the helper into the profile route**

Add the import:

```ts
import { loadOfficialMutualFollowers } from "@/lib/social/profile-mutual-followers";
```

Extend the existing `Promise.all` without changing any current query object.
Change only its destructuring line from four fields to five:

```diff
- const [rawPosts, totalCount, likedCount, viewerFollow] = await Promise.all([
+ const [rawPosts, totalCount, likedCount, viewerFollow, mutualFollowers] = await Promise.all([
```

After the existing fourth `viewerFollow` expression, append this exact fifth
expression before the closing `]);`:

```ts
loadOfficialMutualFollowers({
  viewerUserId,
  targetUserId: target.id,
  isOfficial,
  isOwner,
}),
```

Do not alter the existing `feedPost.findMany` selects or filters. Add the field
next to `isFollowing` in the response:

```ts
isFollowing: Boolean(viewerFollow),
mutualFollowers,
```

- [ ] **Step 5: Run backend tests and lint**

Run:

```powershell
npx tsx --test tests/public-profile-mutual-followers.test.ts tests/brand-user.test.ts
npx eslint 'lib/social/profile-mutual-followers.ts' 'app/api/u/[username]/route.ts' 'tests/public-profile-mutual-followers.test.ts'
```

Expected: tests PASS and ESLint exits 0.

- [ ] **Step 6: Commit Task 1**

```powershell
git add -- 'lib/social/profile-mutual-followers.ts' 'app/api/u/[username]/route.ts' 'tests/public-profile-mutual-followers.test.ts'
git commit -m "feat(profile): expose official mutual followers"
```

---

### Task 2: Flutter mutual parsing and viewer-safe reset

**Files:**
- Modify: `flutter_app/lib/models/public_profile.dart`
- Modify: `flutter_app/lib/services/profile_service.dart:44-78`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart:54-63,264-284`
- Create: `flutter_app/test/models/public_profile_test.dart`
- Modify: `flutter_app/test/screens/public_profile_sync_test.dart`

**Interfaces:**
- Produces `PublicProfileMutualFollower` and `PublicProfileMutualSummary`.
- `PublicProfile.mutualFollowers` is never null.
- Viewer generation reset replaces mutual summary with `PublicProfileMutualSummary.empty` before refetch.

- [ ] **Step 1: Write failing model/parser tests**

Create `flutter_app/test/models/public_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';

void main() {
  test('parses mutual follower summary defensively', () {
    final summary = PublicProfileMutualSummary.fromJson({
      'items': [
        {
          'id': 'user-1',
          'name': 'Mona',
          'username': 'mona',
          'profilePhotoUrl': 'https://cdn.example/mona.jpg',
          'isOfficial': false,
        },
      ],
      'totalCount': 7,
    });
    expect(summary.items.single.id, 'user-1');
    expect(summary.items.single.username, 'mona');
    expect(summary.totalCount, 7);
  });

  test('missing and malformed mutual data falls back to empty', () {
    expect(
      PublicProfileMutualSummary.fromJson(null),
      PublicProfileMutualSummary.empty,
    );
    expect(
      PublicProfileMutualSummary.fromJson({'items': 'bad'}),
      PublicProfileMutualSummary.empty,
    );
  });

  test('summary count cannot be smaller than parsed items', () {
    final summary = PublicProfileMutualSummary.fromJson({
      'items': [
        {'id': 'user-1', 'name': 'Mona'},
        {'id': 'user-2', 'name': 'Riko'},
      ],
      'totalCount': 1,
    });
    expect(summary.totalCount, 2);
  });
}
```

Add to `public_profile_sync_test.dart`:

```dart
test('viewer rebase clears viewer-specific mutual followers', () {
  const profile = PublicProfile(
    id: 'official-1',
    name: 'Natalo Petshop Official',
    isOfficial: true,
    mutualFollowers: PublicProfileMutualSummary(
      items: [
        PublicProfileMutualFollower(id: 'user-1', name: 'Mona'),
      ],
      totalCount: 1,
    ),
  );
  final rebased = rebasePublicProfileForViewer(
    profile,
    viewerId: 'viewer-2',
  );
  expect(rebased.mutualFollowers, PublicProfileMutualSummary.empty);
});
```

- [ ] **Step 2: Run the focused tests and confirm RED**

```powershell
Set-Location flutter_app
flutter test test/models/public_profile_test.dart test/screens/public_profile_sync_test.dart
```

Expected: FAIL because the mutual classes and field do not exist.

- [ ] **Step 3: Add immutable mutual models**

Add before `PublicProfile` in `public_profile.dart`:

```dart
class PublicProfileMutualFollower {
  final String id;
  final String name;
  final String? username;
  final String? profilePhotoUrl;
  final bool isOfficial;

  const PublicProfileMutualFollower({
    required this.id,
    required this.name,
    this.username,
    this.profilePhotoUrl,
    this.isOfficial = false,
  });

  factory PublicProfileMutualFollower.fromJson(Map<String, dynamic> json) {
    return PublicProfileMutualFollower(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      username: _nullableString(json['username']),
      profilePhotoUrl: _nullableString(json['profilePhotoUrl']),
      isOfficial: json['isOfficial'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileMutualFollower &&
          other.id == id &&
          other.name == name &&
          other.username == username &&
          other.profilePhotoUrl == profilePhotoUrl &&
          other.isOfficial == isOfficial;

  @override
  int get hashCode =>
      Object.hash(id, name, username, profilePhotoUrl, isOfficial);
}

class PublicProfileMutualSummary {
  final List<PublicProfileMutualFollower> items;
  final int totalCount;

  const PublicProfileMutualSummary({
    this.items = const [],
    this.totalCount = 0,
  });

  static const empty = PublicProfileMutualSummary();

  factory PublicProfileMutualSummary.fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic> || raw['items'] is! List) return empty;
    final items = <PublicProfileMutualFollower>[];
    for (final item in raw['items'] as List) {
      if (item is Map<String, dynamic>) {
        final parsed = PublicProfileMutualFollower.fromJson(item);
        if (parsed.id.isNotEmpty && parsed.name.isNotEmpty) items.add(parsed);
      }
    }
    final parsedCount = (raw['totalCount'] as num?)?.toInt() ?? 0;
    return PublicProfileMutualSummary(
      items: List.unmodifiable(items),
      totalCount: parsedCount < items.length ? items.length : parsedCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileMutualSummary &&
          other.totalCount == totalCount &&
          _sameMutualItems(other.items, items);

  @override
  int get hashCode => Object.hash(totalCount, Object.hashAll(items));
}

bool _sameMutualItems(
  List<PublicProfileMutualFollower> left,
  List<PublicProfileMutualFollower> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
```

Add to `PublicProfile` constructor, `fromJson`, and `copyWith`:

```dart
final PublicProfileMutualSummary mutualFollowers;

this.mutualFollowers = PublicProfileMutualSummary.empty,

PublicProfileMutualSummary? mutualFollowers,

mutualFollowers: mutualFollowers ?? this.mutualFollowers,
```

- [ ] **Step 4: Parse the top-level response and clear on viewer change**

In `ProfileService.fetchPublicProfile`, add the summary to the existing
`copyWith`:

```dart
final mutualFollowers =
    PublicProfileMutualSummary.fromJson(data['mutualFollowers']);
final profile = PublicProfile.fromJson(userRaw, isOwner: isOwner).copyWith(
  postCount: (stats['postCount'] as num?)?.toInt() ?? 0,
  likedCount: (stats['likedCount'] as num?)?.toInt() ?? 0,
  followersCount: (stats['followersCount'] as num?)?.toInt() ?? 0,
  followingCount: (stats['followingCount'] as num?)?.toInt() ?? 0,
  isFollowing: isFollowing,
  mutualFollowers: mutualFollowers,
);
```

Update `rebasePublicProfileForViewer`:

```dart
return profile.copyWith(
  isFollowing: false,
  isOwner: viewerId != null && viewerId == profile.id,
  mutualFollowers: PublicProfileMutualSummary.empty,
);
```

- [ ] **Step 5: Run focused tests and analyzer**

```powershell
flutter test test/models/public_profile_test.dart test/screens/public_profile_sync_test.dart
flutter analyze lib/models/public_profile.dart lib/services/profile_service.dart lib/screens/public_profile_screen.dart
```

Expected: all tests PASS and analyzer reports no issues.

- [ ] **Step 6: Commit Task 2**

```powershell
Set-Location ..
git add -- 'flutter_app/lib/models/public_profile.dart' 'flutter_app/lib/services/profile_service.dart' 'flutter_app/lib/screens/public_profile_screen.dart' 'flutter_app/test/models/public_profile_test.dart' 'flutter_app/test/screens/public_profile_sync_test.dart'
git commit -m "feat(profile): parse viewer-safe mutual followers"
```

---

### Task 3: Compact expanded headers and action matrix

**Files:**
- Create: `flutter_app/lib/widgets/public_profile_mutual_followers_row.dart`
- Create: `flutter_app/lib/widgets/public_profile_expanded_header.dart`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart:7-35,865-878,992-1675`
- Create: `flutter_app/test/widgets/public_profile_expanded_header_test.dart`

**Interfaces:**
- Produces `PublicProfileExpandedHeader` with callbacks `onFollowToggle`, `onFollowersTap`, `onFollowingTap`, `onEditProfile`, `onShareProfile`, and `onMessage`.
- Removes `onOpenCatalog` completely.
- `onMessage` is rendered only for official non-owner when `chatEnabled` is true.

- [ ] **Step 1: Write failing action/header tests**

Create a harness in `public_profile_expanded_header_test.dart` and assert these
four exact cases:

```dart
testWidgets('official public renders mutuals, message, and no catalog CTA',
    (tester) async {
  var messageCount = 0;
  await tester.pumpWidget(headerHarness(
    profile: const PublicProfile(
      id: 'official-1',
      name: 'Natalo Petshop Official',
      isOfficial: true,
      isFollowing: true,
      mutualFollowers: PublicProfileMutualSummary(
        items: [
          PublicProfileMutualFollower(id: 'user-1', name: 'Mona'),
          PublicProfileMutualFollower(id: 'user-2', name: 'Riko'),
        ],
        totalCount: 7,
      ),
    ),
    chatEnabled: true,
    onMessage: () => messageCount += 1,
  ));
  expect(find.text('Pesan'), findsOneWidget);
  expect(find.textContaining('Diikuti oleh'), findsOneWidget);
  expect(find.text('Lihat Etalase Produk'), findsNothing);
  await tester.tap(find.text('Pesan'));
  expect(messageCount, 1);
});

testWidgets('regular public has no message and no mutual row', (tester) async {
  await tester.pumpWidget(headerHarness(
    profile: const PublicProfile(
      id: 'user-1',
      name: 'Mona',
      username: 'mona',
    ),
    chatEnabled: true,
  ));
  expect(find.text('Pesan'), findsNothing);
  expect(find.textContaining('Diikuti oleh'), findsNothing);
  expect(find.text('Ikuti'), findsOneWidget);
});

testWidgets('official owner gets edit and never follow or message',
    (tester) async {
  await tester.pumpWidget(headerHarness(
    profile: const PublicProfile(
      id: 'official-1',
      name: 'Natalo Petshop Official',
      isOfficial: true,
      isOwner: true,
    ),
    chatEnabled: true,
    onEditProfile: () {},
  ));
  expect(find.text('Edit Profil'), findsOneWidget);
  expect(find.text('Ikuti'), findsNothing);
  expect(find.text('Pesan'), findsNothing);
});

testWidgets('empty optional rows leave no replacement spacing', (tester) async {
  await tester.pumpWidget(headerHarness(
    profile: const PublicProfile(
      id: 'official-1',
      name: 'Natalo Petshop Official',
      isOfficial: true,
    ),
    chatEnabled: false,
  ));
  expect(find.byKey(const Key('official_mutual_row')), findsNothing);
  expect(find.byKey(const Key('official_message_button')), findsNothing);
  expect(tester.takeException(), isNull);
});
```

The harness must provide Material theme, width 320/393, and callbacks without
network access. Use this exact harness signature:

```dart
Widget headerHarness({
  required PublicProfile profile,
  bool chatEnabled = false,
  VoidCallback? onMessage,
  VoidCallback? onEditProfile,
  double width = 393,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        padding: const EdgeInsets.only(top: 59, bottom: 34),
        textScaler: textScaler,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: PublicProfileExpandedHeader(
              profile: profile,
              followBusy: false,
              chatEnabled: chatEnabled,
              onFollowToggle: () {},
              onFollowersTap: () {},
              onFollowingTap: () {},
              onEditProfile: onEditProfile,
              onShareProfile: () {},
              onMessage: onMessage,
            ),
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Run the focused header test and confirm RED**

```powershell
Set-Location flutter_app
flutter test test/widgets/public_profile_expanded_header_test.dart
```

Expected: FAIL because the extracted widgets and new constructor do not exist.

- [ ] **Step 3: Build the mutual row with deterministic copy**

Create `public_profile_mutual_followers_row.dart` with this public interface:

```dart
class PublicProfileMutualFollowersRow extends StatelessWidget {
  final PublicProfileMutualSummary summary;

  const PublicProfileMutualFollowersRow({
    super.key,
    required this.summary,
  });

  static String copyFor(PublicProfileMutualSummary summary) {
    final names = summary.items.map((item) => item.name).take(2).toList();
    if (names.isEmpty) return '';
    if (summary.totalCount <= 1) return 'Diikuti oleh ${names.first}';
    if (summary.totalCount == 2 && names.length == 2) {
      return 'Diikuti oleh ${names.first} dan ${names.last}';
    }
    final remaining = summary.totalCount - names.length;
    return 'Diikuti oleh ${names.join(', ')}, dan $remaining lainnya';
  }

  @override
  Widget build(BuildContext context) {
    if (summary.items.isEmpty || summary.totalCount <= 0) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: copyFor(summary),
      child: Row(
        key: const Key('official_mutual_row'),
        children: [
          SizedBox(
            width: 58,
            height: 30,
            child: Stack(
              children: [
                for (var index = 0; index < summary.items.take(3).length; index++)
                  Positioned(
                    left: index * 18,
                    child: ProfileAvatar(
                      initial: summary.items[index].name[0].toUpperCase(),
                      imageUrl: summary.items[index].profilePhotoUrl,
                      isOfficial: summary.items[index].isOfficial,
                      plain: true,
                      size: 30,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              copyFor(summary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Extract and compact the expanded header**

Create `public_profile_expanded_header.dart` with this stable constructor:

```dart
class PublicProfileExpandedHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final bool chatEnabled;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;

  const PublicProfileExpandedHeader({
    super.key,
    required this.profile,
    required this.followBusy,
    required this.chatEnabled,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
  });

  bool get _showOfficialMessage =>
      profile.isOfficial && !profile.isOwner && chatEnabled && onMessage != null;

  @override
  Widget build(BuildContext context) {
    return profile.isOfficial
        ? _OfficialExpandedHeader(
            profile: profile,
            followBusy: followBusy,
            onFollowToggle: profile.isOwner ? null : onFollowToggle,
            onFollowersTap: onFollowersTap,
            onFollowingTap: onFollowingTap,
            onEditProfile: profile.isOwner ? onEditProfile : null,
            onShareProfile: onShareProfile,
            onMessage: _showOfficialMessage ? onMessage : null,
          )
        : _RegularExpandedHeader(
            profile: profile,
            followBusy: followBusy,
            onFollowToggle: profile.isOwner ? null : onFollowToggle,
            onFollowersTap: onFollowersTap,
            onFollowingTap: onFollowingTap,
            onEditProfile: profile.isOwner ? onEditProfile : null,
            onShareProfile: onShareProfile,
          );
  }
}
```

Move the existing follow spinner and stat behavior into this file. Apply exact
layout rules from the spec: official avatar 78, regular avatar 78, official
bio maxLines 1 at normal scale/2 above 1.3, regular bio maxLines 3, visual
buttons 40 high with an outer 44-high semantic tap area, slim stats without
the old translucent card, and no `onOpenCatalog` field.

- [ ] **Step 5: Replace screen-local header classes and wire chat**

In `public_profile_screen.dart`:

```dart
import '../state/chat_store.dart';
import '../widgets/public_profile_expanded_header.dart';
```

Provide the header through an `AnimatedBuilder` so the kill switch is live:

```dart
AnimatedBuilder(
  animation: chatStore,
  builder: (context, child) => PublicProfileExpandedHeader(
    profile: profile,
    followBusy: _followBusy,
    chatEnabled: chatStore.chatEnabled,
    onFollowToggle: profile.isOwner ? null : _toggleFollow,
    onFollowersTap: () => _openFollowList(FollowListKind.followers),
    onFollowingTap: () => _openFollowList(FollowListKind.following),
    onEditProfile: profile.isOwner
        ? () => Navigator.pushNamed(context, '/member/profile')
        : null,
    onShareProfile: _shareProfile,
    onMessage: profile.isOfficial && !profile.isOwner
        ? () => Navigator.pushNamed(context, '/chat')
        : null,
  ),
)
```

Delete the old `PublicProfileExpandedHeader`, `_OfficialHeader`, `_OfficialStat`,
`_FollowButtonContent`, `_Avatar`, and `_StatColumn` definitions from the
screen only after the extracted widget compiles.

- [ ] **Step 6: Run responsive header tests and analyzer**

```powershell
flutter test test/widgets/public_profile_expanded_header_test.dart
flutter analyze lib/widgets/public_profile_expanded_header.dart lib/widgets/public_profile_mutual_followers_row.dart lib/screens/public_profile_screen.dart
```

Expected: PASS with no overflow at widths 320 and 393 and no analyzer issues.

- [ ] **Step 7: Commit Task 3 and run the first review checkpoint**

```powershell
Set-Location ..
git add -- 'flutter_app/lib/widgets/public_profile_expanded_header.dart' 'flutter_app/lib/widgets/public_profile_mutual_followers_row.dart' 'flutter_app/lib/screens/public_profile_screen.dart' 'flutter_app/test/widgets/public_profile_expanded_header_test.dart'
git commit -m "feat(profile): compact public profile identities"
```

Review checkpoint: verify action matrix, no dead bell, no catalog CTA, no fake
mutuals, and official-owner Edit Profil behavior before continuing.

---

### Task 4: Deterministic scroll motion model

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_header_motion.dart`
- Modify: `flutter_app/test/widgets/public_profile_header_motion_test.dart`

**Interfaces:**
- Produces `PublicProfileHeaderMotion.resolve(scrollOffset:, collapseDistance:, reducedMotion:)`.
- Provides `tabTravel`, `labelOpacity`, `pillOpacity`, `underlineOpacity`, `glassOpacity`, `compactIdentityOpacity`, `controlSurfaceOpacity`, and `blurSigma`.

- [ ] **Step 1: Replace tests with exact staged-motion expectations**

Add tests for 0/25/50/75/100%, reverse equality, monotonic fields, clamp, and
reduced motion:

```dart
test('expanded and collapsed endpoints match final choreography', () {
  final expanded = PublicProfileHeaderMotion.resolve(
    scrollOffset: 0,
    collapseDistance: 240,
    reducedMotion: false,
  );
  final collapsed = PublicProfileHeaderMotion.resolve(
    scrollOffset: 240,
    collapseDistance: 240,
    reducedMotion: false,
  );
  expect(expanded.tabTravel, 0);
  expect(expanded.labelOpacity, 0);
  expect(expanded.pillOpacity, 0);
  expect(expanded.underlineOpacity, 1);
  expect(expanded.blurSigma, 0);
  expect(collapsed.tabTravel, 1);
  expect(collapsed.labelOpacity, 1);
  expect(collapsed.pillOpacity, 1);
  expect(collapsed.underlineOpacity, 0);
  expect(collapsed.glassOpacity, 1);
  expect(collapsed.compactIdentityOpacity, 1);
  expect(collapsed.blurSigma, 12);
});

test('reverse scroll resolves byte-for-byte equal values', () {
  final forward = PublicProfileHeaderMotion.resolve(
    scrollOffset: 120,
    collapseDistance: 240,
    reducedMotion: false,
  );
  final reverse = PublicProfileHeaderMotion.resolve(
    scrollOffset: 120,
    collapseDistance: 240,
    reducedMotion: false,
  );
  expect(reverse, forward);
});

test('reduced motion uses linear progress and disables animated blur', () {
  final motion = PublicProfileHeaderMotion.resolve(
    scrollOffset: 60,
    collapseDistance: 240,
    reducedMotion: true,
  );
  expect(motion.progress, 0.25);
  expect(motion.blurSigma, 0);
  expect(motion.glassOpacity, greaterThanOrEqualTo(0));
});
```

- [ ] **Step 2: Run the motion test and confirm RED**

```powershell
Set-Location flutter_app
flutter test test/widgets/public_profile_header_motion_test.dart
```

Expected: FAIL because the new named signature and fields do not exist.

- [ ] **Step 3: Implement the pure staged motion model**

Use this implementation shape:

```dart
import 'dart:ui' show lerpDouble;

class PublicProfileHeaderMotion {
  const PublicProfileHeaderMotion._({
    required this.progress,
    required this.tabTravel,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    required this.glassOpacity,
    required this.compactIdentityOpacity,
    required this.controlSurfaceOpacity,
    required this.blurSigma,
  });

  final double progress;
  final double tabTravel;
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final double glassOpacity;
  final double compactIdentityOpacity;
  final double controlSurfaceOpacity;
  final double blurSigma;

  static PublicProfileHeaderMotion resolve({
    required double scrollOffset,
    required double collapseDistance,
    required bool reducedMotion,
  }) {
    final raw = collapseDistance <= 0
        ? (scrollOffset <= 0 ? 0.0 : 1.0)
        : (scrollOffset / collapseDistance).clamp(0.0, 1.0).toDouble();
    final progress = reducedMotion ? raw : raw * raw * (3 - 2 * raw);
    final tabTravel = _interval(progress, 0.20, 0.78);
    final labelOpacity = _interval(progress, 0.45, 0.78);
    final pillOpacity = _interval(progress, 0.38, 0.78);
    final underlineOpacity = 1 - _interval(progress, 0.20, 0.52);
    final glassOpacity = _interval(progress, 0.50, 0.88);
    final compactIdentityOpacity = _interval(progress, 0.72, 0.94);
    final controlSurfaceOpacity = _interval(progress, 0.50, 0.88);
    return PublicProfileHeaderMotion._(
      progress: progress,
      tabTravel: tabTravel,
      labelOpacity: labelOpacity,
      pillOpacity: pillOpacity,
      underlineOpacity: underlineOpacity,
      glassOpacity: glassOpacity,
      compactIdentityOpacity: compactIdentityOpacity,
      controlSurfaceOpacity: controlSurfaceOpacity,
      blurSigma: reducedMotion ? 0 : lerpDouble(0, 12, glassOpacity)!,
    );
  }

  static double _interval(double value, double begin, double end) {
    if (value <= begin) return 0;
    if (value >= end) return 1;
    return ((value - begin) / (end - begin)).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileHeaderMotion &&
          other.progress == progress &&
          other.tabTravel == tabTravel &&
          other.labelOpacity == labelOpacity &&
          other.pillOpacity == pillOpacity &&
          other.underlineOpacity == underlineOpacity &&
          other.glassOpacity == glassOpacity &&
          other.compactIdentityOpacity == compactIdentityOpacity &&
          other.controlSurfaceOpacity == controlSurfaceOpacity &&
          other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(
        progress,
        tabTravel,
        labelOpacity,
        pillOpacity,
        underlineOpacity,
        glassOpacity,
        compactIdentityOpacity,
        controlSurfaceOpacity,
        blurSigma,
      );
}
```

- [ ] **Step 4: Run tests and commit Task 4**

```powershell
flutter test test/widgets/public_profile_header_motion_test.dart
Set-Location ..
git add -- 'flutter_app/lib/widgets/public_profile_header_motion.dart' 'flutter_app/test/widgets/public_profile_header_motion_test.dart'
git commit -m "feat(profile): define premium scroll choreography"
```

---

### Task 5: Public-only three-pill tab presentation

**Files:**
- Create: `flutter_app/lib/widgets/public_profile_content_tab_bar.dart`
- Create: `flutter_app/test/widgets/public_profile_content_tab_bar_test.dart`
- Test unchanged: `flutter_app/test/widgets/profile_content_tab_bar_test.dart`

**Interfaces:**
- Produces `PublicProfileContentTabBar(controller:, isOfficial:, labelOpacity:, pillOpacity:, underlineOpacity:, onTap:)`.
- Leaves `ProfileContentTabBar` and `ProfileContentTabHeaderDelegate` behavior unchanged for `MemberScreen`.

- [ ] **Step 1: Write failing visual-state tests**

The new test must assert:

```dart
testWidgets('expanded public tabs are icon-only and neutral', (tester) async {
  await tester.pumpWidget(tabHarness(
    isOfficial: false,
    labelOpacity: 0,
    pillOpacity: 0,
    underlineOpacity: 1,
  ));
  expect(find.text('Postingan'), findsNothing);
  expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
  expect(find.byKey(const Key('public_tab_expanded_underline')), findsOneWidget);
  expect(find.byType(BackdropFilter), findsNothing);
});

testWidgets('collapsed tabs render three individual neutral pills',
    (tester) async {
  await tester.pumpWidget(tabHarness(
    isOfficial: true,
    labelOpacity: 1,
    pillOpacity: 1,
    underlineOpacity: 0,
  ));
  expect(find.text('Postingan'), findsOneWidget);
  expect(find.text('Video'), findsOneWidget);
  expect(find.text('Belanja'), findsOneWidget);
  expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
  expect(find.byKey(const Key('public_tab_video_pill')), findsOneWidget);
  expect(find.byKey(const Key('public_tab_shop_pill')), findsOneWidget);
  expect(find.byKey(const Key('public_tab_shared_surface')), findsNothing);
  expect(find.byKey(const Key('public_tab_expanded_underline')), findsNothing);
});

testWidgets('collapsed tabs fit width 320 at text scale 2', (tester) async {
  await tester.pumpWidget(tabHarness(
    width: 320,
    textScaler: const TextScaler.linear(2),
    isOfficial: false,
    labelOpacity: 1,
    pillOpacity: 1,
    underlineOpacity: 0,
  ));
  expect(tester.takeException(), isNull);
  expect(tester.getRect(find.byType(PublicProfileContentTabBar)).left, 0);
});
```

Also inspect all `Icon` and `Text` foregrounds and assert none equals
`NataloColors.primary`.

- [ ] **Step 2: Run the new test and confirm RED**

```powershell
Set-Location flutter_app
flutter test test/widgets/public_profile_content_tab_bar_test.dart
```

Expected: FAIL because `PublicProfileContentTabBar` does not exist.

- [ ] **Step 3: Implement public-only tabs**

Create the widget with fixed 52-high layout, horizontal padding 16 supplied by
the overlay, and three flex children. Use this stable constructor:

```dart
class PublicProfileContentTabBar extends StatelessWidget {
  static const double height = 52;

  final TabController controller;
  final bool isOfficial;
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final ValueChanged<int>? onTap;

  const PublicProfileContentTabBar({
    super.key,
    required this.controller,
    required this.isOfficial,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    this.onTap,
  });
}
```

The build method must use a transparent `TabBar` and three `_PublicProfileTab`
children. Each child owns its pill `DecoratedBox`; the parent must not draw a
surface. Resolve colors as:

```dart
final brightness = Theme.of(context).brightness;
final expandedForeground = isOfficial
    ? Colors.white
    : Theme.of(context).colorScheme.onSurface;
final activeSurface = brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.90)
    : const Color(0xFF111111).withValues(alpha: 0.92);
final activeForeground =
    brightness == Brightness.dark ? const Color(0xFF111111) : Colors.white;
final inactiveSurface = brightness == Brightness.dark
    ? const Color(0xFF202124).withValues(alpha: 0.78)
    : Colors.white.withValues(alpha: 0.84);
final inactiveForeground = brightness == Brightness.dark
    ? Colors.white
    : const Color(0xFF2C2C2C);
```

Inside `_PublicProfileTab`, use `controller.animation` emphasis to lerp active
and inactive neutral colors. Render the expanded underline only when
`underlineOpacity > 0.001`. Cap only the compact visual label scaler:

```dart
final scale = MediaQuery.textScalerOf(context).scale(1);
final labelScaler = TextScaler.linear(scale.clamp(1.0, 1.3));
```

Keep full semantic labels and `selected: emphasis > 0.5` outside the capped
visual `MediaQuery`.

- [ ] **Step 4: Verify public tabs and member tabs together**

```powershell
flutter test test/widgets/public_profile_content_tab_bar_test.dart test/widgets/profile_content_tab_bar_test.dart
flutter analyze lib/widgets/public_profile_content_tab_bar.dart lib/widgets/profile_content_tab_bar.dart
```

Expected: both suites PASS; existing member tab test remains unchanged.

- [ ] **Step 5: Commit Task 5**

```powershell
Set-Location ..
git add -- 'flutter_app/lib/widgets/public_profile_content_tab_bar.dart' 'flutter_app/test/widgets/public_profile_content_tab_bar_test.dart'
git commit -m "feat(profile): add neutral public profile pills"
```

---

### Task 6: True glass overlay and screen integration

**Files:**
- Create: `flutter_app/lib/widgets/public_profile_chrome_overlay.dart`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart:782-918`
- Delete: `flutter_app/lib/widgets/public_profile_collapsing_header.dart`
- Create: `flutter_app/test/widgets/public_profile_chrome_overlay_test.dart`
- Delete: `flutter_app/test/widgets/public_profile_collapsing_header_test.dart`

**Interfaces:**
- Produces `PublicProfileHeaderMetrics.resolve(context, profile)` and `PublicProfileChromeOverlay`.
- Overlay receives current `scrollOffset` and never owns a timer/controller.
- Screen uses one outer `SliverToBoxAdapter`, one overlay `AnimatedBuilder`, and existing `TabBarView`.

- [ ] **Step 1: Write failing overlay tests**

Cover expanded/intermediate/collapsed at 0/25/50/75/100%, reverse equality,
one `BackdropFilter`, no solid collapsed strip, right-to-left travel, selected
tab retention, 320/360/393/430 widths, dark mode, and reduced motion:

```dart
testWidgets('collapsed chrome uses one blur layer above underlapping grid',
    (tester) async {
  await tester.pumpWidget(overlayHarness(
    width: 393,
    scrollOffset: 280,
    isOfficial: true,
  ));
  expect(find.byType(BackdropFilter), findsOneWidget);
  expect(find.byKey(const Key('public_profile_glass_layer')), findsOneWidget);
  expect(find.byKey(const Key('public_profile_grid_underlay')), findsOneWidget);
  expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
});

testWidgets('right edge moves left monotonically and reverses exactly',
    (tester) async {
  final rights = <double>[];
  for (final fraction in <double>[0, .25, .5, .75, 1]) {
    await tester.pumpWidget(overlayHarness(
      width: 393,
      scrollOffset: 240 * fraction,
      isOfficial: false,
    ));
    rights.add(tester.getRect(
      find.byKey(const Key('public_profile_tab_group')),
    ).right);
  }
  expect(rights[1], lessThanOrEqualTo(rights[0]));
  expect(rights[2], lessThanOrEqualTo(rights[1]));
  expect(rights[3], lessThanOrEqualTo(rights[2]));
  expect(rights[4], lessThanOrEqualTo(rights[3]));
  await tester.pumpWidget(overlayHarness(
    width: 393,
    scrollOffset: 120,
    isOfficial: false,
  ));
  expect(
    tester.getRect(find.byKey(const Key('public_profile_tab_group'))).right,
    rights[2],
  );
});

testWidgets('reduced motion removes blur but retains readable tint',
    (tester) async {
  await tester.pumpWidget(overlayHarness(
    width: 360,
    scrollOffset: 240,
    isOfficial: false,
    disableAnimations: true,
  ));
  expect(find.byType(BackdropFilter), findsNothing);
  expect(find.byKey(const Key('public_profile_reduced_motion_tint')),
      findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run overlay tests and confirm RED**

```powershell
Set-Location flutter_app
flutter test test/widgets/public_profile_chrome_overlay_test.dart
```

Expected: FAIL because the overlay does not exist.

- [ ] **Step 3: Implement deterministic metrics and overlay**

Create `public_profile_chrome_overlay.dart` with these interfaces:

```dart
class PublicProfileHeaderMetrics {
  final double topPadding;
  final double toolbarHeight;
  final double identityHeight;
  final double tabHeight;

  const PublicProfileHeaderMetrics({
    required this.topPadding,
    required this.toolbarHeight,
    required this.identityHeight,
    required this.tabHeight,
  });

  double get collapsedChromeHeight => topPadding + toolbarHeight + tabHeight;
  double get scrollSpaceHeight => collapsedChromeHeight + identityHeight;

  static PublicProfileHeaderMetrics resolve(
    BuildContext context,
    PublicProfile profile,
  ) {
    final scale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 2.0)
        .toDouble();
    final hasBio = profile.bio?.trim().isNotEmpty == true;
    final hasMutuals = profile.isOfficial &&
        !profile.isOwner &&
        profile.mutualFollowers.items.isNotEmpty;
    final base = profile.isOfficial ? 210.0 : 156.0;
    final bio = hasBio ? (profile.isOfficial ? 28.0 : 48.0) : 0.0;
    final mutual = hasMutuals ? 40.0 : 0.0;
    final scaleAllowance = (scale - 1) * (profile.isOfficial ? 72 : 64);
    return PublicProfileHeaderMetrics(
      topPadding: MediaQuery.paddingOf(context).top,
      toolbarHeight: 56,
      identityHeight: base + bio + mutual + scaleAllowance,
      tabHeight: PublicProfileContentTabBar.height,
    );
  }
}

class PublicProfileChromeOverlay extends StatelessWidget {
  final PublicProfile profile;
  final TabController controller;
  final double scrollOffset;
  final PublicProfileHeaderMetrics metrics;
  final VoidCallback onBack;
  final VoidCallback? onShareProfile;
  final VoidCallback? onOverflow;
  final ValueChanged<int>? onTabTap;

  const PublicProfileChromeOverlay({
    super.key,
    required this.profile,
    required this.controller,
    required this.scrollOffset,
    required this.metrics,
    required this.onBack,
    this.onShareProfile,
    this.onOverflow,
    this.onTabTap,
  });
}
```

Resolve motion with `collapseDistance: metrics.identityHeight`. Position tabs
using:

```dart
final expandedTop = metrics.topPadding +
    metrics.toolbarHeight +
    metrics.identityHeight;
final collapsedTop = metrics.topPadding + metrics.toolbarHeight;
final tabTop = lerpDouble(expandedTop, collapsedTop, motion.tabTravel)!;
```

Derive both horizontal insets from the same travel value. This moves the right
edge left while keeping all states inside the viewport:

```dart
final horizontalInset = lerpDouble(0, 16, motion.tabTravel)!;
final tabLeft = horizontalInset;
final tabRight = horizontalInset;
```

Build exactly one glass layer clipped to `metrics.collapsedChromeHeight`. When
`disableAnimations` is true, render a translucent `ColoredBox` with key
`public_profile_reduced_motion_tint`; otherwise render one `BackdropFilter`
with key `public_profile_glass_layer`. Put toolbar and tab group above it.
Expanded official toolbar hides duplicate title; compact official title/logo
fade with `motion.compactIdentityOpacity`. Regular handle remains present.

- [ ] **Step 4: Replace the pinned solid sliver with scroll space + overlay**

In `_buildBody`, compute metrics once per build and use this structure:

```dart
final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
final scrollView = Stack(
  children: [
    RepaintBoundary(
      key: const Key('public_profile_grid_underlay'),
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: profile.isOfficial
                    ? null
                    : Theme.of(context).colorScheme.surface,
                gradient: profile.isOfficial
                    ? NataloColors.heroGradientV
                    : null,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: metrics.topPadding + metrics.toolbarHeight,
                  ),
                  SizedBox(
                    height: metrics.identityHeight,
                    child: AnimatedBuilder(
                      animation: chatStore,
                      builder: (context, child) => PublicProfileExpandedHeader(
                        profile: profile,
                        followBusy: _followBusy,
                        chatEnabled: chatStore.chatEnabled,
                        onFollowToggle:
                            profile.isOwner ? null : _toggleFollow,
                        onFollowersTap: () =>
                            _openFollowList(FollowListKind.followers),
                        onFollowingTap: () =>
                            _openFollowList(FollowListKind.following),
                        onEditProfile: profile.isOwner
                            ? () => Navigator.pushNamed(
                                  context,
                                  '/member/profile',
                                )
                            : null,
                        onShareProfile: _shareProfile,
                        onMessage: profile.isOfficial && !profile.isOwner
                            ? () => Navigator.pushNamed(context, '/chat')
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(height: metrics.tabHeight),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: _profileContentTabs.map(_buildContentPage).toList(),
        ),
      ),
    ),
    Positioned.fill(
      child: AnimatedBuilder(
        animation: _scrollController,
        builder: (context, child) => PublicProfileChromeOverlay(
          profile: profile,
          controller: _tabController,
          scrollOffset: _scrollController.hasClients
              ? _scrollController.offset
                  .clamp(0.0, double.infinity)
                  .toDouble()
              : 0,
          metrics: metrics,
          onBack: () => Navigator.maybePop(context),
          onShareProfile: _shareProfile,
          onOverflow:
              !profile.isOwner && !profile.isOfficial ? _openModeration : null,
          onTabTap: _onTabTapped,
        ),
      ),
    ),
  ],
);
```

Delete the old `PublicProfileCollapsingHeaderDelegate` import/file only after
all references are gone. Preserve the existing official pull-to-refresh
backdrop logic, but key it to the new metrics and ensure it is hidden after
the grid underlaps.

- [ ] **Step 5: Run real-scroll integration tests**

Update `public_profile_screen_test.dart` to set:

```dart
VisibilityDetectorController.instance.updateInterval = Duration.zero;
addTearDown(() {
  VisibilityDetectorController.instance.updateInterval =
      const Duration(milliseconds: 500);
});
```

Add a test that pumps an initial result, drags the actual
`NestedScrollView`, verifies the three labels appear, drags back, and verifies
selected tab and first grid tile remain unchanged.

Move the public navigation assertion from the deleted delegate test into the
screen test:

```dart
final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
expect(scaffold.bottomNavigationBar, isNull);
```

Run:

```powershell
flutter test test/widgets/public_profile_chrome_overlay_test.dart test/screens/public_profile_screen_test.dart test/screens/public_profile_sync_test.dart test/screens/public_profile_video_prewarm_test.dart
flutter analyze lib/widgets/public_profile_chrome_overlay.dart lib/widgets/public_profile_content_tab_bar.dart lib/screens/public_profile_screen.dart
```

Expected: all tests PASS, no pending timer, no overflow, analyzer clean.

- [ ] **Step 6: Commit Task 6 and run the second review checkpoint**

```powershell
Set-Location ..
git add -- 'flutter_app/lib/widgets/public_profile_chrome_overlay.dart' 'flutter_app/lib/screens/public_profile_screen.dart' 'flutter_app/test/widgets/public_profile_chrome_overlay_test.dart' 'flutter_app/test/screens/public_profile_screen_test.dart'
git rm -- 'flutter_app/lib/widgets/public_profile_collapsing_header.dart' 'flutter_app/test/widgets/public_profile_collapsing_header_test.dart'
git commit -m "feat(profile): underlap grid beneath glass chrome"
```

Review checkpoint: inspect actual widget tree for exactly one blur, no full
screen hit-test blocker, no grid rebuild per scroll, stable reverse geometry,
and unchanged TabController/prewarm behavior.

---

### Task 7: Golden, responsive, regression, and rollout verification

**Files:**
- Create: `flutter_app/test/golden/public_profile_premium_test.dart`
- Create: `flutter_app/test/golden/public_profile_official_expanded.png`
- Create: `flutter_app/test/golden/public_profile_official_collapsed.png`
- Create: `flutter_app/test/golden/public_profile_regular_expanded.png`
- Create: `flutter_app/test/golden/public_profile_regular_collapsed.png`
- Create: `flutter_app/test/screens/member_profile_navigation_regression_test.dart`

**Interfaces:**
- Produces four deterministic iPhone 15 Pro golden baselines.
- Produces final verification evidence; no product behavior is added here.

- [ ] **Step 1: Add four deterministic golden states**

Use `393x852`, DPR 3, top safe area 59, bottom 34, Plus Jakarta Sans loaded
through app theme, fixed profile data, fixed grid assets/colors, and
`VisibilityDetectorController.instance.updateInterval = Duration.zero`.
Render expanded with `scrollOffset: 0` and collapsed with
`scrollOffset: metrics.identityHeight`.

The four assertions must be:

```dart
expect(
  find.byKey(const Key('official_expanded_golden')),
  matchesGoldenFile('public_profile_official_expanded.png'),
);
expect(
  find.byKey(const Key('official_collapsed_golden')),
  matchesGoldenFile('public_profile_official_collapsed.png'),
);
expect(
  find.byKey(const Key('regular_expanded_golden')),
  matchesGoldenFile('public_profile_regular_expanded.png'),
);
expect(
  find.byKey(const Key('regular_collapsed_golden')),
  matchesGoldenFile('public_profile_regular_collapsed.png'),
);
```

- [ ] **Step 2: Generate and inspect golden baselines**

```powershell
Set-Location flutter_app
flutter test --update-goldens test/golden/public_profile_premium_test.dart
flutter test test/golden/public_profile_premium_test.dart
```

Expected: PASS. Visually inspect each PNG for compact density, official navy
expanded, regular neutral expanded, transparent glass collapsed, three pills,
no blue, no collapsed underline, and 1 px grid gaps.

- [ ] **Step 3: Run the complete focused regression suite**

Before running it, create the self-profile navigation regression test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/widgets/bottom_nav.dart';

void main() {
  testWidgets('member profile retains account bottom navigation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    expect(find.byType(BottomNavBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
```

```powershell
flutter test test/models/public_profile_test.dart test/widgets/public_profile_expanded_header_test.dart test/widgets/public_profile_header_motion_test.dart test/widgets/public_profile_content_tab_bar_test.dart test/widgets/profile_content_tab_bar_test.dart test/widgets/public_profile_chrome_overlay_test.dart test/widgets/profile_grid_geometry_test.dart test/screens/public_profile_screen_test.dart test/screens/public_profile_sync_test.dart test/screens/public_profile_video_prewarm_test.dart test/screens/member_profile_navigation_regression_test.dart test/golden/public_profile_premium_test.dart
```

Expected: all tests PASS.

- [ ] **Step 4: Run full Flutter analyzer and test suite**

```powershell
flutter analyze
flutter test
```

Expected: analyzer exits 0 and complete suite PASS. If unrelated pre-existing
failures occur, record the exact failing test and prove the focused suite still
passes; do not modify unrelated dirty files.

- [ ] **Step 5: Run backend regression**

```powershell
Set-Location ..
npx tsx --test tests/public-profile-mutual-followers.test.ts tests/brand-user.test.ts
npm test
```

Expected: focused tests and full backend suite PASS.

- [ ] **Step 6: Perform device-size and interaction QA**

Verify through widget tests or a local Android device/emulator:

```text
320x800  light  textScale 1.0/1.3/2.0
360x800  light/dark  textScale 1.0/1.3/2.0
393x852  light/dark  safeTop 59 safeBottom 34
430x932  light/dark  textScale 1.0/1.3
```

For each relevant profile: slow scroll, fast flick, reverse at 25/50/75%, tap
and swipe tabs during motion, pull-to-refresh, follow toggle, share, official
Pesan, guest login return, and overflow moderation. Confirm no blank spacing,
white/navy flash, clipped copy, dead controls, grid jump, or pointer blocker.

- [ ] **Step 7: Profile animation performance**

Run Flutter in profile mode on the available Android device:

```powershell
Set-Location flutter_app
flutter run --profile
```

In DevTools Performance, record slow scroll and fast flick across collapse.
Pass criteria: one blur layer, no screen-wide rebuild per frame, no repeated
shader compilation after warm-up, and no sustained UI/raster frame over the
device frame budget. iPhone 15 Pro verification is completed via the next
Codemagic/TestFlight build.

- [ ] **Step 8: Commit Task 7**

```powershell
Set-Location ..
git add -- 'flutter_app/test/golden/public_profile_premium_test.dart' 'flutter_app/test/golden/public_profile_official_expanded.png' 'flutter_app/test/golden/public_profile_official_collapsed.png' 'flutter_app/test/golden/public_profile_regular_expanded.png' 'flutter_app/test/golden/public_profile_regular_collapsed.png' 'flutter_app/test/screens/member_profile_navigation_regression_test.dart'
git commit -m "test(profile): lock premium public profile states"
```

## Final Review and Deployment Order

1. Run `review-code-changes` on the complete diff.
2. Run `superpowers:requesting-code-review` with a reviewer focused on spec
   compliance, then a second reviewer focused on Flutter rebuild/paint cost.
3. Apply valid findings using `superpowers:receiving-code-review` and rerun the
   affected focused suite plus full analyzer.
4. Run `superpowers:verification-before-completion` before claiming complete.
5. Deploy backend first so `mutualFollowers` is available; older Flutter builds
   ignore the extra response field.
6. Build/deploy Flutter after backend health is confirmed. The Flutter parser
   remains compatible with a backend response that lacks the field.
7. Validate on iPhone 15 Pro through Codemagic/TestFlight: safe area, 120 Hz
   scroll, glass contrast over bright/dark thumbnails, `/chat` handoff, and
   reverse gesture.

## Expected Commit Sequence

```text
feat(profile): expose official mutual followers
feat(profile): parse viewer-safe mutual followers
feat(profile): compact public profile identities
feat(profile): define premium scroll choreography
feat(profile): add neutral public profile pills
feat(profile): underlap grid beneath glass chrome
test(profile): lock premium public profile states
```
