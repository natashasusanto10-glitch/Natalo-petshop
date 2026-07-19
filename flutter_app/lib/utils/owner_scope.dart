import 'dart:convert';

/// Owner-scoping for on-device (SharedPreferences) cache keys.
///
/// Historically many caches used a single global key (e.g.
/// `recently_viewed_v1`), so account A's data leaked to account B and to
/// guest sessions on the same device. [key] namespaces a base key by the
/// current owner: `guest` when signed out, or `m_<base64url(memberId)>` for
/// a signed-in member.
///
/// The member id is base64url-encoded so ids containing odd characters can
/// never collide with the guest namespace, produce an invalid key, or leak
/// verbatim. Legacy unscoped keys are intentionally NOT read by callers —
/// they belong to no known owner and must not be claimed by whoever happens
/// to be logged in.
class OwnerScope {
  const OwnerScope._();

  /// Namespace tag for [memberId]. Guest (signed out) => `guest`.
  static String ownerTag(String? memberId) {
    final id = memberId?.trim();
    if (id == null || id.isEmpty) return 'guest';
    return 'm_${base64Url.encode(utf8.encode(id))}';
  }

  /// Owner-namespaced storage key: `<baseKey>::<ownerTag>`.
  static String key(String baseKey, String? memberId) {
    return '$baseKey::${ownerTag(memberId)}';
  }
}
