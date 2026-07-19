import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(memberStore.debugResetServerLogout);

  test('logout attempts server logout when a token exists, then clears local',
      () async {
    memberStore.debugSetSessionToken('old-token');
    var serverCalled = false;
    memberStore.debugServerLogout = () async {
      // Token must still be present at call time so apiClient can carry it.
      expect(memberStore.sessionToken, 'old-token');
      serverCalled = true;
    };

    await memberStore.logout();

    expect(serverCalled, isTrue);
    expect(memberStore.sessionToken, isNull);
    expect(memberStore.isLoggedIn, isFalse);
  });

  test('local state is always cleared even if server logout throws', () async {
    memberStore.debugSetSessionToken('old-token');
    memberStore.debugServerLogout = () async {
      throw Exception('network down');
    };

    await memberStore.logout();

    expect(memberStore.sessionToken, isNull);
    expect(memberStore.isLoggedIn, isFalse);
  });

  test('no server logout attempt when there is no token', () async {
    memberStore.debugSetSessionToken(null);
    var serverCalled = false;
    memberStore.debugServerLogout = () async {
      serverCalled = true;
    };

    await memberStore.logout();

    expect(serverCalled, isFalse);
  });
}
