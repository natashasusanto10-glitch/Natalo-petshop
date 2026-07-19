import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/state/account_scope.dart';
import 'package:natalo_petshop_flutter/state/recently_viewed_store.dart';

Product _p(String id) => Product(
      id: id,
      slug: id,
      title: id,
      category: 'c',
      brand: 'b',
      imageUrl: '',
      price: 1000,
      rating: 0,
      reviewCount: 0,
      stock: 1,
      description: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(debugResetAccountOwnerId);

  test('recently-viewed is isolated per account and guest', () async {
    String? owner = 'account-A';
    debugSetAccountOwnerId(() => owner);
    final store = recentlyViewedStore;

    await store.debugSyncOwner(); // adopt A
    await store.add(_p('prod-A'));
    expect(store.items.map((e) => e.id), ['prod-A']);

    owner = 'account-B'; // switch account
    await store.debugSyncOwner();
    expect(store.items, isEmpty, reason: 'B must not see A history');
    await store.add(_p('prod-B'));
    expect(store.items.map((e) => e.id), ['prod-B']);

    owner = 'account-A'; // back to A
    await store.debugSyncOwner();
    expect(store.items.map((e) => e.id), ['prod-A'],
        reason: 'A restored from its own key, no B leakage');

    owner = null; // guest
    await store.debugSyncOwner();
    expect(store.items, isEmpty, reason: 'guest starts clean');
  });

  test('debugSyncOwner is a no-op when the owner is unchanged', () async {
    String? owner = 'same-acct';
    debugSetAccountOwnerId(() => owner);
    final store = recentlyViewedStore;

    await store.debugSyncOwner();
    await store.add(_p('x'));
    await store.debugSyncOwner(); // same owner → data retained
    expect(store.items.map((e) => e.id), ['x']);
  });
}
