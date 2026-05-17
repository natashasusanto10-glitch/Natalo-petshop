import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Notification preferences screen — toggle per kategori push:
/// - Update Pesanan (status order, pengiriman)
/// - Promo & Diskon (flash sale, kupon)
/// - Voucher Baru (voucher member tier)
/// - Newsletter (artikel blog, tips)
///
/// Preferences persisted di SharedPreferences. Backend masih kirim
/// FCM ke semua subscriber — filtering di client side (notif tetap
/// masuk tapi tidak di-display kalau kategori off). Production lebih
/// baik server-side filtering by reading prefs via API.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  static const _kPrefix = 'natalo_notif_pref_';
  // Default: semua kategori ON.
  final Map<String, bool> _prefs = {
    'order': true,
    'promo': true,
    'voucher': true,
    'newsletter': false, // less critical, default off
  };

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1. Load lokal SharedPreferences dulu (instant first paint).
    final prefs = await SharedPreferences.getInstance();
    for (final key in _prefs.keys.toList()) {
      final stored = prefs.getBool('$_kPrefix$key');
      if (stored != null) _prefs[key] = stored;
    }
    if (mounted) setState(() => _loading = false);
    // 2. Sync dari server di background — kalau ada perbedaan, server wins.
    // Server-side filter lebih reliable dari client-only (push tetap diterima
    // tapi tidak di-display = waste battery + bandwidth).
    try {
      final serverPrefs = await notificationService.fetchPreferences();
      if (!mounted || serverPrefs.isEmpty) return;
      bool changed = false;
      for (final entry in serverPrefs.entries) {
        if (_prefs.containsKey(entry.key) && _prefs[entry.key] != entry.value) {
          _prefs[entry.key] = entry.value;
          await prefs.setBool('$_kPrefix${entry.key}', entry.value);
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    } catch (_) {
      // Endpoint mungkin belum aktif di backend — silent fallback ke local.
    }
  }

  Future<void> _toggle(String key, bool value) async {
    AppHaptics.tap();
    setState(() => _prefs[key] = value);
    // Persist lokal dulu (instant feedback).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kPrefix$key', value);
    // Sync ke server (fire-and-forget). Backend simpan + filter push notif
    // sebelum kirim ke device → server-side filtering hemat battery user.
    await notificationService.updatePreferences(Map.from(_prefs));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Pengaturan Notifikasi'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _CategoryHeader(),
                _PrefTile(
                  icon: Icons.local_shipping_rounded,
                  color: const Color(0xFF2563EB),
                  bg: const Color(0xFFEAF5FF),
                  title: 'Update Pesanan',
                  subtitle: 'Status order, packing, pengiriman, sampai',
                  value: _prefs['order']!,
                  onChanged: (v) => _toggle('order', v),
                ),
                _PrefTile(
                  icon: Icons.local_offer_rounded,
                  color: const Color(0xFFDB2777),
                  bg: const Color(0xFFFDF2F8),
                  title: 'Promo & Diskon',
                  subtitle: 'Flash sale, harga member, brand deals',
                  value: _prefs['promo']!,
                  onChanged: (v) => _toggle('promo', v),
                ),
                _PrefTile(
                  icon: Icons.card_giftcard_rounded,
                  color: const Color(0xFFEA580C),
                  bg: const Color(0xFFFFF7ED),
                  title: 'Voucher Baru',
                  subtitle: 'Voucher member tier dan reward poin',
                  value: _prefs['voucher']!,
                  onChanged: (v) => _toggle('voucher', v),
                ),
                _PrefTile(
                  icon: Icons.menu_book_rounded,
                  color: const Color(0xFFCA8A04),
                  bg: const Color(0xFFFEFCE8),
                  title: 'Tips & Newsletter',
                  subtitle: 'Artikel blog, tips perawatan hewan',
                  value: _prefs['newsletter']!,
                  onChanged: (v) => _toggle('newsletter', v),
                ),
                const SizedBox(height: 16),
                // Test push button — kirim notif ke device sendiri.
                // Berguna untuk verify subscription works setelah enable
                // notifikasi (terutama kalau channel-level dimute di system).
                const SizedBox(height: 16),
                _TestPushButton(),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _brandBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: _brandBlue,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notifikasi keamanan akun (login dari device baru, password berubah) tetap aktif untuk keamanan.',
                          style: TextStyle(
                            color: _brandBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        'Pilih notifikasi yang ingin diterima',
        style: TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrefTile({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppPressable(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(20),
        child: GlassSurface(
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: _brandBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Test push notification button — kirim notif ke device sendiri lewat
/// endpoint POST /api/push/me/test. Show subscription status di subtitle.
class _TestPushButton extends StatefulWidget {
  @override
  State<_TestPushButton> createState() => _TestPushButtonState();
}

class _TestPushButtonState extends State<_TestPushButton> {
  bool _sending = false;
  PushSubscriptionStatus? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await pushNotificationService.fetchSubscriptionStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _send() async {
    AppHaptics.tap();
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await pushNotificationService.sendTestPush(
      title: 'Test Notifikasi Natalo',
      body: 'Kalau kamu lihat ini, push notif kamu jalan! 🎉',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Test terkirim — cek notification tray dalam beberapa detik.'
            : 'Gagal kirim test. Pastikan kamu sudah login + izin notif aktif.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = _status?.subscribed == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _brandBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.send_rounded, color: _brandBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Test Notifikasi',
                  style: TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _status == null
                      ? 'Mengecek subscription...'
                      : subscribed
                          ? 'Subscribed (${_status!.tokenCount} device). Tap untuk test.'
                          : 'Belum subscribed — login dulu untuk aktifkan.',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Kirim'),
            ),
          ),
        ],
      ),
    );
  }
}
