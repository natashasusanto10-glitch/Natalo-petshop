import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
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
  static const _catOrder = 'order';
  static const _catPromo = 'promo';
  static const _catVoucher = 'voucher';
  static const _catProduct = 'product';
  static const _catLoyalty = 'loyalty_points';
  static const _catChat = 'chat';
  static const _catFeed = 'feed';

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

      final serverPrefs = await notificationService.fetchPreferences();
      if (!mounted || serverPrefs.isEmpty) return;
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
    _orderUpdates = values[_catOrder] ?? _orderUpdates;
    _promoVoucher = values[_catVoucher] ?? values[_catPromo] ?? _promoVoucher;
    _newProduct = values[_catProduct] ?? _newProduct;
    _loyaltyPoints = values[_catLoyalty] ?? _loyaltyPoints;
    _chatMessages = values[_catChat] ?? _chatMessages;
    _feedActivity = values[_catFeed] ?? _feedActivity;
  }

  Future<void> _persistAll(SharedPreferences prefs) async {
    for (final entry in _currentPreferences().entries) {
      await prefs.setBool(_prefKey(entry.key), entry.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Preferensi Notifikasi'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'Anda dapat mengubah pengaturan kapan saja. Notifikasi penting (mis. status pesanan) tetap dikirim untuk keamanan transaksi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: NataloColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: NataloColors.textSecondary,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE8F8)),
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
          style: const TextStyle(
            color: NataloColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: NataloColors.textSecondary,
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
