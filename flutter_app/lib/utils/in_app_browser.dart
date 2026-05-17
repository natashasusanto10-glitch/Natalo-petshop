import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../screens/in_app_browser_screen.dart';
import 'haptics.dart';

/// Helper untuk buka halaman static Natalo (Blog, Help, Kebijakan, dll)
/// di in-app browser. Resolve relative path → absolute via publicSiteUrl.
class AppInAppBrowser {
  /// Open URL absolute atau path relatif (mis. `/bantuan`).
  /// [title] muncul di header browser — fallback ke title HTML page kalau null.
  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
    bool haptic = true,
  }) async {
    if (haptic) AppHaptics.tap();
    final fullUrl = _resolveUrl(url);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => InAppBrowserScreen(url: fullUrl, title: title),
      ),
    );
  }

  /// Shortcut routes ke halaman static Natalo yang sering di-akses.
  static Future<void> openBantuan(BuildContext context) =>
      open(context, url: '/bantuan', title: 'Bantuan');

  static Future<void> openTentangNatalo(BuildContext context) =>
      open(context, url: '/tentang-kami', title: 'Tentang Natalo');

  static Future<void> openCaraPemesanan(BuildContext context) =>
      open(context, url: '/cara-pemesanan', title: 'Cara Pemesanan');

  static Future<void> openKebijakanPrivasi(BuildContext context) =>
      open(context, url: '/kebijakan-privasi', title: 'Kebijakan Privasi');

  static Future<void> openKebijakanPengembalian(BuildContext context) =>
      open(context,
          url: '/kebijakan-pengembalian', title: 'Kebijakan Pengembalian');

  static Future<void> openBlog(BuildContext context) =>
      open(context, url: '/blog', title: 'Blog Natalo');

  static String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    final base = ApiConfig.publicSiteUrl.endsWith('/')
        ? ApiConfig.publicSiteUrl.substring(0, ApiConfig.publicSiteUrl.length - 1)
        : ApiConfig.publicSiteUrl;
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }
}
