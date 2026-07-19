import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/services/block_service.dart';
import 'package:natalo_petshop_flutter/state/account_scope.dart';
import 'package:natalo_petshop_flutter/state/feed_local_store.dart';
import 'package:natalo_petshop_flutter/state/search_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(debugResetAccountOwnerId);

  test('search history is isolated per account and guest', () async {
    String? owner = 'A';
    debugSetAccountOwnerId(() => owner);
    final s = searchHistoryStore;

    await s.debugSyncOwner();
    await s.push('makanan kucing');
    expect(s.entries, ['makanan kucing']);

    owner = 'B';
    await s.debugSyncOwner();
    expect(s.entries, isEmpty, reason: 'B must not see A queries');
    await s.push('pasir gumpal');

    owner = 'A';
    await s.debugSyncOwner();
    expect(s.entries, ['makanan kucing'], reason: 'A restored, no B leakage');

    owner = null;
    await s.debugSyncOwner();
    expect(s.entries, isEmpty, reason: 'guest clean');
  });

  test('block list is isolated per account', () async {
    String? owner = 'A';
    debugSetAccountOwnerId(() => owner);
    final b = blockService;

    await b.debugSyncOwner();
    await b.blockUser(userId: 'bad-user-1');
    expect(b.isUserBlocked(userId: 'bad-user-1'), isTrue);

    owner = 'B';
    await b.debugSyncOwner();
    expect(b.isUserBlocked(userId: 'bad-user-1'), isFalse,
        reason: 'B does not inherit A block list');

    owner = 'A';
    await b.debugSyncOwner();
    expect(b.isUserBlocked(userId: 'bad-user-1'), isTrue);
  });

  test('feed likes + viewed session reset on account switch', () async {
    String? owner = 'A';
    debugSetAccountOwnerId(() => owner);
    final f = feedLocalStore;
    f.debugResetForTest();

    await f.setLiked('post-1', true);
    f.markViewedThisSession('post-1');
    expect(f.isLiked('post-1'), isTrue);
    expect(f.hasViewedThisSession('post-1'), isTrue);

    owner = 'B';
    await f.debugSyncOwner();
    expect(f.isLiked('post-1'), isFalse, reason: 'B must not inherit A likes');
    expect(f.hasViewedThisSession('post-1'), isFalse,
        reason: 'viewed dedupe reset on viewer change');
    await f.setLiked('post-2', true);

    owner = 'A';
    await f.debugSyncOwner();
    expect(f.isLiked('post-1'), isTrue);
    expect(f.isLiked('post-2'), isFalse, reason: 'A must not see B likes');

    owner = null;
    await f.debugSyncOwner();
    expect(f.isLiked('post-1'), isFalse, reason: 'guest clean');
  });
}
