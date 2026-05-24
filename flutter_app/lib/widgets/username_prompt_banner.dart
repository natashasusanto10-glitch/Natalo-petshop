import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/member_store.dart';
import '../utils/haptics.dart';

const _bannerBg = Color(0xFFF5F3FF); // soft purple-blue
const _bannerBorder = Color(0xFFE0E7FF);
const _bannerAccent = Color(0xFF5B5BD6);
const _bannerText = Color(0xFF1E1B4B);

/// Key SharedPreferences untuk snooze banner. Value = unix millis
/// kapan banner boleh muncul lagi. User dismiss → set to now + 7 days.
const _snoozeKey = 'username_banner_snooze_until_ms';

/// Banner reminder buat user yang belum set @username. Tampil di
/// Member/Akun screen header (paling atas). Dismissible — snooze 7
/// hari, simpan di SharedPreferences local.
///
/// Auto-hide kalau:
///   - User belum login (memberStore.profile null)
///   - User sudah punya username
///   - User dismiss → snooze sampai 7 hari ke depan
///
/// Tap "Atur sekarang" → route ke /member/username (setup screen
/// dedicated). Setelah save, memberStore.profile.username updated →
/// AnimatedBuilder rebuild → banner auto-disappear.
class UsernamePromptBanner extends StatefulWidget {
  const UsernamePromptBanner({super.key});

  @override
  State<UsernamePromptBanner> createState() => _UsernamePromptBannerState();
}

class _UsernamePromptBannerState extends State<UsernamePromptBanner> {
  bool _snoozed = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadSnooze();
  }

  Future<void> _loadSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_snoozeKey);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!mounted) return;
      setState(() {
        _snoozed = until != null && until > now;
        _initialized = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _initialized = true);
    }
  }

  Future<void> _dismiss() async {
    AppHaptics.tap();
    final until = DateTime.now().add(const Duration(days: 7));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_snoozeKey, until.millisecondsSinceEpoch);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _snoozed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();
    if (_snoozed) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        final profile = memberStore.profile;
        if (profile == null) return const SizedBox.shrink();
        if (profile.hasUsername) return const SizedBox.shrink();
        return _BannerBody(
          onPickNow: () {
            AppHaptics.tap();
            Navigator.pushNamed(context, '/member/username');
          },
          onDismiss: _dismiss,
        );
      },
    );
  }
}

class _BannerBody extends StatelessWidget {
  final VoidCallback onPickNow;
  final VoidCallback onDismiss;

  const _BannerBody({
    required this.onPickNow,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: _bannerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bannerBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _bannerBorder),
            ),
            child: const Icon(
              Icons.alternate_email_rounded,
              color: _bannerAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih @username kamu',
                  style: TextStyle(
                    color: _bannerText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Biar bisa di-mention di feed dan punya link profil sendiri.',
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: onPickNow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _bannerAccent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Atur sekarang',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onDismiss,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Text(
                          'Nanti aja',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            iconSize: 18,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Tutup (snooze 7 hari)',
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
