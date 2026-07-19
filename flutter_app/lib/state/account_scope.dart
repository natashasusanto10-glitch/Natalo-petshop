import 'package:flutter/foundation.dart';

import 'member_store.dart';

/// Indirection for "who owns the on-device caches right now".
///
/// Production wiring resolves the current member id from [memberStore]; unit
/// tests override [accountOwnerId] so account A/B/guest switches can be driven
/// deterministically without MemberStore's async hydration + networking.
String? Function() accountOwnerId = () => memberStore.profile?.id;

@visibleForTesting
void debugSetAccountOwnerId(String? Function() provider) {
  accountOwnerId = provider;
}

@visibleForTesting
void debugResetAccountOwnerId() {
  accountOwnerId = () => memberStore.profile?.id;
}
