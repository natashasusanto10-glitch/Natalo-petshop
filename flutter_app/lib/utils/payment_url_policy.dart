/// Pure, side-effect-free URL security policy for payments and the embedded
/// WebView. No Flutter/plugin imports so it is trivially unit-testable and
/// can be reasoned about in isolation.
///
/// Two threat surfaces are covered:
///  1. Midtrans payment links — only exact Snap origins are trusted; a
///     validated link is opened in the OS browser, never inside our WebView.
///  2. Embedded WebView navigations — only Natalo origins may render inside
///     the app; foreign https opens externally, and dangerous schemes
///     (javascript:, data:, file:, intent:, plain http, …) are rejected.
class PaymentUrlPolicy {
  const PaymentUrlPolicy._();

  /// Exact Midtrans Snap hosts. No wildcards, no subdomain matching.
  static const Set<String> _midtransHosts = {
    'app.midtrans.com',
    'app.sandbox.midtrans.com',
  };

  /// First-party Natalo hosts allowed to render inside the embedded WebView.
  static const Set<String> _nataloHosts = {
    'natalopetshop.com',
    'www.natalopetshop.com',
  };

  /// Schemes we are willing to hand to the OS from the embedded WebView.
  /// Deliberately excludes `http` (must be TLS) and all scripting/local
  /// schemes.
  static const Set<String> _safeExternalSchemes = {'https', 'mailto', 'tel'};

  /// Exact validation of a Midtrans payment URL before it is trusted.
  ///
  /// Requires: HTTPS, no userInfo, default port (implicit or 443), an exact
  /// Snap host, and a `/snap/` path prefix. Everything else is rejected —
  /// including lookalike hosts, credential-stuffing userInfo, and foreign
  /// schemes.
  static bool isValidMidtransPaymentUrl(String? raw) {
    final uri = _parseStrict(raw);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;
    if (uri.hasPort && uri.port != 443) return false;
    if (!_midtransHosts.contains(uri.host.toLowerCase())) return false;
    return uri.path.startsWith('/snap/');
  }

  /// Whether [raw] may be loaded *inside* the embedded WebView. Only first
  /// party Natalo origins qualify. [extraHosts] lets the caller add the
  /// configured public-site/api host at runtime.
  static bool isAllowedEmbeddedNavigation(
    String? raw, {
    Set<String>? extraHosts,
  }) {
    final uri = _parseStrict(raw);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;
    if (uri.hasPort && uri.port != 443) return false;
    final host = uri.host.toLowerCase();
    if (_nataloHosts.contains(host)) return true;
    if (extraHosts != null) {
      for (final h in extraHosts) {
        if (h.toLowerCase() == host) return true;
      }
    }
    return false;
  }

  /// Whether a navigation that is *not* allowed inside the WebView should be
  /// handed to the OS (external browser / dialer / mail). Dangerous and
  /// non-TLS schemes return false so the caller simply drops them.
  static bool shouldOpenExternally(String? raw) {
    final uri = _parseStrict(raw);
    if (uri == null) return false;
    if (uri.userInfo.isNotEmpty) return false;
    return _safeExternalSchemes.contains(uri.scheme);
  }

  static Uri? _parseStrict(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme.isEmpty) return null;
    return uri;
  }
}
