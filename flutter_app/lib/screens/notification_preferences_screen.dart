import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Preferensi Notifikasi — toggle push notification per kategori, persist
/// ke SharedPreferences supaya survive app restart.
///
/// TODO future: sync ke FCM topic subscribe/unsubscribe + backend
/// `PATCH /api/member/notification-preferences` saat endpoint ready.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  // Pref keys — versioned supaya safe untuk schema migration nanti.
  static const _kPrefix = 'notif_pref_v1_';
  static const _kOrderUpdates = '${_kPrefix}order_updates';
  static const _kPromoVoucher = '${_kPrefix}promo_voucher';
  static const _kNewProduct = '${_kPrefix}new_product';
  static const _kLoyaltyPoints = '${_kPrefix}loyalty_points';
  static const _kChatMessages = '${_kPrefix}chat_messages';
  static const _kFeedActivity = '${_kPrefix}feed_activity';

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
      setState(() {
        // Default true untuk notif penting (order, voucher, loyalty, chat).
        // Default false untuk discoverable (new product, feed activity).
        _orderUpdates = prefs.getBool(_kOrderUpdates) ?? true;
        _promoVoucher = prefs.getBool(_kPromoVoucher) ?? true;
        _newProduct = prefs.getBool(_kNewProduct) ?? false;
        _loyaltyPoints = prefs.getBool(_kLoyaltyPoints) ?? true;
        _chatMessages = prefs.getBool(_kChatMessages) ?? true;
        _feedActivity = prefs.getBool(_kFeedActivity) ?? false;
      });
    } catch (_) {
      // Disk error — pakai default, lanjut tetap render.
    }
  }

  Future<void> _savePref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Silent. UI state sudah update via setState — disk fail nanti hilang
      // saat restart, user bisa toggle ulang. Tidak block flow.
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
          _SectionLabel('Pesanan'),
          _ToggleTile(
            icon: Icons.receipt_long_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: 'Update Status Pesanan',
            subtitle: 'PAID, DIKIRIM, SAMPAI, dst.',
            value: _orderUpdates,
            onChanged: (v) {
              setState(() => _orderUpdates = v);
              _savePref(_kOrderUpdates, v);
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
              _savePref(_kChatMessages, v);
            },
          ),
          const SizedBox(height: 16),
          _SectionLabel('Promo & Voucher'),
          _ToggleTile(
            icon: Icons.local_offer_outlined,
            iconColor: const Color(0xFFEC4899),
            title: 'Voucher Baru',
            subtitle: 'Notif kalau ada voucher diskon atau gratis ongkir.',
            value: _promoVoucher,
            onChanged: (v) {
              setState(() => _promoVoucher = v);
              _savePref(_kPromoVoucher, v);
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
              _savePref(_kLoyaltyPoints, v);
            },
          ),
          const SizedBox(height: 16),
          _SectionLabel('Produk & Konten'),
          _ToggleTile(
            icon: Icons.fiber_new_rounded,
            iconColor: const Color(0xFF16A34A),
            title: 'Produk Baru',
            subtitle: 'Notif rilis produk baru / restock favorit.',
            value: _newProduct,
            onChanged: (v) {
              setState(() => _newProduct = v);
              _savePref(_kNewProduct, v);
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
              _savePref(_kFeedActivity, v);
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
