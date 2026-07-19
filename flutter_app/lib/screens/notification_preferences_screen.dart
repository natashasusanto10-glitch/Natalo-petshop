import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Preferensi Notifikasi — toggle push notification per kategori.
/// Key lokal sengaja sama dengan `push_notification_service` agar filter push
/// benar-benar mengikuti preferensi user.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  static const _kPrefix = 'natalo_notif_pref_';
  static const _catMaster = 'master';
  static const _catOrder = 'order';
  static const _catPromo = 'promo';
  static const _catVoucher = 'voucher';
  static const _catProduct = 'product';
  static const _catLoyalty = 'loyalty_points';
  static const _catChat = 'chat';
  static const _catFeed = 'feed';

  /// Master switch — kalau OFF, semua kategori jadi disabled (tidak terima
  /// notif apapun selain critical seperti security alerts). Default ON.
  bool _masterEnabled = true;
  bool _orderUpdates = true;
  bool _promoVoucher = true;
  bool _newProduct = false;
  bool _loyaltyPoints = true;
  bool _chatMessages = true;
  bool _feedActivity = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _applyPreferencesFromLocal(prefs));

      // Server = source of truth HANYA kalau benar-benar menjawab dengan
      // data. `null` berarti fetch gagal / endpoint 404 / response kosong —
      // dalam kasus itu JANGAN sentuh state; pilihan lokal user (yang barusan
      // dari disk) tetap dipakai. Sebelumnya fungsi ini mengembalikan default
      // saat gagal, lalu di-persist, sehingga toggle product/feed selalu
      // ke-reset ke OFF tiap halaman dibuka ulang.
      final serverPrefs = await notificationService.fetchPreferences();
      if (!mounted || serverPrefs == null) return;
      setState(() => _applyPreferences(serverPrefs));
      await _persistAll(prefs);
    } catch (_) {
      // Disk error — pakai default, lanjut tetap render.
    }
  }

  Future<void> _savePref(String category, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey(category), value);
      await notificationService.updatePreferences(_currentPreferences());
    } catch (_) {
      // Silent. UI state sudah update via setState — disk fail nanti hilang
      // saat restart, user bisa toggle ulang. Tidak block flow.
    }
  }

  String _prefKey(String category) => '$_kPrefix$category';

  Map<String, bool> _currentPreferences() {
    return {
      _catMaster: _masterEnabled,
      _catOrder: _orderUpdates,
      _catPromo: _promoVoucher,
      _catVoucher: _promoVoucher,
      _catProduct: _newProduct,
      _catLoyalty: _loyaltyPoints,
      _catChat: _chatMessages,
      _catFeed: _feedActivity,
    };
  }

  void _applyPreferencesFromLocal(SharedPreferences prefs) {
    _applyPreferences({
      _catMaster: prefs.getBool(_prefKey(_catMaster)) ?? true,
      _catOrder: prefs.getBool(_prefKey(_catOrder)) ?? true,
      _catPromo: prefs.getBool(_prefKey(_catPromo)) ?? true,
      _catVoucher: prefs.getBool(_prefKey(_catVoucher)) ?? true,
      _catProduct: prefs.getBool(_prefKey(_catProduct)) ?? false,
      _catLoyalty: prefs.getBool(_prefKey(_catLoyalty)) ?? true,
      _catChat: prefs.getBool(_prefKey(_catChat)) ?? true,
      _catFeed: prefs.getBool(_prefKey(_catFeed)) ?? false,
    });
  }

  void _applyPreferences(Map<String, bool> values) {
    _masterEnabled = values[_catMaster] ?? _masterEnabled;
    _orderUpdates = values[_catOrder] ?? _orderUpdates;
    _promoVoucher = values[_catVoucher] ?? values[_catPromo] ?? _promoVoucher;
    _newProduct = values[_catProduct] ?? _newProduct;
    _loyaltyPoints = values[_catLoyalty] ?? _loyaltyPoints;
    _chatMessages = values[_catChat] ?? _chatMessages;
    _feedActivity = values[_catFeed] ?? _feedActivity;
  }

  Future<void> _resetToDefault() async {
    AppHaptics.tap();
    setState(() {
      _masterEnabled = true;
      _orderUpdates = true;
      _promoVoucher = true;
      _newProduct = false;
      _loyaltyPoints = true;
      _chatMessages = true;
      _feedActivity = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistAll(prefs);
      await notificationService.updatePreferences(_currentPreferences());
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preferensi notifikasi dikembalikan ke default.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _persistAll(SharedPreferences prefs) async {
    for (final entry in _currentPreferences().entries) {
      await prefs.setBool(_prefKey(entry.key), entry.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Preferensi Notifikasi'),
        backgroundColor: isDark ? cs.surface : const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Master switch — Enable/Disable semua notif sekaligus ──
          // Saat OFF, semua per-category toggle jadi disabled (visual:
          // opacity 0.4). Tetap respect "always-on critical" (security
          // alerts) yang bypass master di server side.
          _MasterSwitchCard(
            enabled: _masterEnabled,
            onChanged: (v) {
              AppHaptics.tap();
              setState(() => _masterEnabled = v);
              _savePref(_catMaster, v);
            },
          ),
          const SizedBox(height: 20),
          Opacity(
            opacity: _masterEnabled ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !_masterEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('Pesanan'),
                  _ToggleTile(
                    icon: Icons.receipt_long_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    title: 'Update Status Pesanan',
                    subtitle: 'PAID, DIKIRIM, SAMPAI, dst.',
                    value: _orderUpdates,
                    onChanged: (v) {
                      setState(() => _orderUpdates = v);
                      _savePref(_catOrder, v);
                    },
                  ),
                  _ToggleTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    iconColor: const Color(0xFF1E5FBF),
                    title: 'Chat dari Admin',
                    subtitle: 'Balasan inquiry produk dari Natalo.',
                    value: _chatMessages,
                    onChanged: (v) {
                      setState(() => _chatMessages = v);
                      _savePref(_catChat, v);
                    },
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('Promo & Voucher'),
                  _ToggleTile(
                    icon: Icons.local_offer_outlined,
                    iconColor: const Color(0xFFEC4899),
                    title: 'Voucher Baru',
                    subtitle: 'Notif kalau ada voucher diskon atau gratis ongkir.',
                    value: _promoVoucher,
                    onChanged: (v) {
                      setState(() => _promoVoucher = v);
                      _savePref(_catPromo, v);
                    },
                  ),
                  _ToggleTile(
                    icon: Icons.workspace_premium_outlined,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Poin Loyalty',
                    subtitle: 'Reminder poin earned + voucher hadiah ultah.',
                    value: _loyaltyPoints,
                    onChanged: (v) {
                      setState(() => _loyaltyPoints = v);
                      _savePref(_catLoyalty, v);
                    },
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('Produk & Konten'),
                  _ToggleTile(
                    icon: Icons.fiber_new_rounded,
                    iconColor: const Color(0xFF16A34A),
                    title: 'Produk Baru',
                    subtitle: 'Notif rilis produk baru / restock favorit.',
                    value: _newProduct,
                    onChanged: (v) {
                      setState(() => _newProduct = v);
                      _savePref(_catProduct, v);
                    },
                  ),
                  _ToggleTile(
                    icon: Icons.video_collection_outlined,
                    iconColor: const Color(0xFFD97706),
                    title: 'Feed Activity',
                    subtitle: 'Komentar atau like di postingan Anda.',
                    value: _feedActivity,
                    onChanged: (v) {
                      setState(() => _feedActivity = v);
                      _savePref(_catFeed, v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton.icon(
              onPressed: _resetToDefault,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Kembalikan ke default'),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'Anda dapat mengubah pengaturan kapan saja. Notifikasi penting (mis. konfirmasi keamanan) tetap dikirim demi keamanan akun.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
          // Diagnostik panel — DEBUG BUILD ONLY. Production user tidak
          // perlu lihat raw FCM token / tombol Daftar Ulang / Test push
          // (debugging tool internal, bukan fitur user). `kDebugMode`
          // di-strip oleh tree-shaker saat release, jadi zero overhead
          // untuk APK yang dipublish. Untuk debug remote di lapangan,
          // build APK debug dengan `flutter build apk --debug` lalu kirim
          // ke device target.
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            const _PushDiagnosticPanel(),
          ],
        ],
      ),
    );
  }
}

/// Panel diagnostik push — visible di Pengaturan Notifikasi supaya user
/// (dan saya saat debug) bisa cek cepat apakah token Android FCM ke-
/// register ke backend dengan benar, lalu fire test push untuk validasi
/// chain lengkap (permission → token → backend → FCM → device tray).
///
/// 3 baris status:
///   - Permission OS (granted / denied / not requested)
///   - Token lokal (16 char first untuk privacy)
///   - Token ke-register di backend (count via /api/push/me/status)
/// Plus 2 tombol: Kirim Test + Daftar Ulang Token (force re-register).
class _PushDiagnosticPanel extends StatefulWidget {
  const _PushDiagnosticPanel();

  @override
  State<_PushDiagnosticPanel> createState() => _PushDiagnosticPanelState();
}

class _PushDiagnosticPanelState extends State<_PushDiagnosticPanel> {
  String? _permissionStatus;
  String? _fcmToken;
  PushSubscriptionStatus? _status;
  bool _refreshing = false;
  bool _sending = false;
  bool _reRegistering = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      // Permission OS-level — saat denied, FCM tidak akan deliver notif
      // sama sekali walau token valid.
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      String perm;
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          perm = 'Diizinkan';
          break;
        case AuthorizationStatus.denied:
          perm = 'Ditolak — buka Pengaturan HP → Aplikasi → Natalo → Notifikasi → izinkan';
          break;
        case AuthorizationStatus.notDetermined:
          perm = 'Belum diminta';
          break;
        case AuthorizationStatus.provisional:
          perm = 'Sementara (iOS)';
          break;
      }
      final token = await FirebaseMessaging.instance.getToken();
      final status = await pushNotificationService.fetchSubscriptionStatus();
      if (!mounted) return;
      setState(() {
        _permissionStatus = perm;
        _fcmToken = token;
        _status = status;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionStatus = 'Error: $e';
        _refreshing = false;
      });
    }
  }

  Future<void> _sendTest() async {
    AppHaptics.tap();
    setState(() => _sending = true);
    final ok = await pushNotificationService.sendTestPush(
      title: 'Test Notifikasi Natalo',
      body: Platform.isAndroid
          ? 'Notifikasi Android diterima ✓'
          : 'Notifikasi iOS diterima ✓',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Test terkirim. Tunggu beberapa detik di tray notifikasi.'
              : 'Gagal kirim test push. Cek status di atas.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _reRegister() async {
    AppHaptics.tap();
    setState(() => _reRegistering = true);
    await pushNotificationService.registerWithServer();
    // Delay singkat supaya backend sempat upsert sebelum refetch status.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _reRegistering = false);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Token diminta ulang ke server.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokenPreview = (_fcmToken == null || _fcmToken!.isEmpty)
        ? '(belum ada — FCM getToken null)'
        : '${_fcmToken!.substring(0, _fcmToken!.length.clamp(0, 16))}…';
    final regCount = _status?.tokenCount ?? 0;
    final authed = _status?.authenticated ?? false;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? cs.outlineVariant
              : const Color(0xFFDDE8F8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Diagnostik Push',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh status',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                icon: _refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _refreshing ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _DiagRow('Permission OS', _permissionStatus ?? '...'),
          _DiagRow('Login session', authed ? 'Aktif' : 'Belum login'),
          _DiagRow('FCM token (lokal)', tokenPreview),
          _DiagRow(
            'Token aktif di server',
            _status == null
                ? '...'
                : regCount > 0
                    ? '$regCount device'
                    : 'Belum ada — tap "Daftar Ulang"',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: _reRegistering
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Daftar Ulang'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? cs.outlineVariant
                          : const Color(0xFFCBD5E1),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: _reRegistering ? null : _reRegister,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Kirim Test'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NataloColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: (_sending || regCount == 0) ? null : _sendTest,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Master switch card di top — gradient biru + icon big + toggle.
/// Saat OFF, semua per-category toggle di bawahnya jadi disabled.
class _MasterSwitchCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _MasterSwitchCard({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B7FEA), Color(0xFF075CB5)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFCBD5E1), Color(0xFF94A3B8)],
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (enabled
                    ? const Color(0xFF0B7FEA)
                    : const Color(0xFF64748B))
                .withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              enabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Notifikasi Push',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Aktif — kamu menerima notif sesuai pengaturan.'
                      : 'Nonaktif — semua notif di-mute.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white.withValues(alpha: 0.35),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
            inactiveThumbColor: Colors.white,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? cs.outlineVariant
              : const Color(0xFFDDE8F8),
        ),
      ),
      child: SwitchListTile(
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        value: value,
        activeThumbColor: NataloColors.primary,
        onChanged: (v) {
          AppHaptics.tap();
          onChanged(v);
        },
      ),
    );
  }
}
