import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _kOnboardingSeenKey = 'natalo_onboarding_seen';

/// Onboarding screen — 3 slides intro untuk first-time user.
/// Hanya muncul sekali. Setelah user tap "Mulai", flag di-set di
/// SharedPreferences supaya next launch langsung skip ke home.
///
/// Pattern PWA: tidak punya — karena WebView Capacitor langsung ke /
/// route home. Native bisa kasih first impression yang lebih engaging.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Cek apakah user sudah pernah lihat onboarding. Call di main.dart
  /// untuk decide initialRoute.
  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingSeenKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSeenKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;

  static const _slides = [
    _Slide(
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF2563EB),
      bg: Color(0xFFEAF5FF),
      title: 'Belanja lebih cepat',
      body:
          'Cari produk dengan suara atau scan barcode, checkout 1 tap, semua jadi instan.',
    ),
    _Slide(
      icon: Icons.notifications_active_rounded,
      color: Color(0xFFDB2777),
      bg: Color(0xFFFDF2F8),
      title: 'Tahu duluan kapan paket sampai',
      body:
          'Notifikasi real-time saat pesanan diproses, dikirim, hingga tiba di depan rumah.',
    ),
    _Slide(
      icon: Icons.fingerprint_rounded,
      color: Color(0xFF16A34A),
      bg: Color(0xFFECFDF5),
      title: 'Aman dengan sidik jari',
      body:
          'Login pakai biometric, app auto-lock saat ditinggal, data kamu lebih terjaga.',
    ),
  ];

  void _next() {
    AppHaptics.tap();
    if (_index < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    AppHaptics.success();
    await OnboardingScreen.markSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  Future<void> _skip() async {
    AppHaptics.tap();
    await OnboardingScreen.markSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button top-right
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                child: TextButton(
                  onPressed: _skip,
                  child: const Text(
                    'Lewati',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            // Slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  AppHaptics.tap();
                },
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Big circle icon
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            color: s.bg,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: s.color.withValues(alpha: 0.12),
                                blurRadius: 30,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Icon(s.icon, color: s.color, size: 88),
                        ),
                        const SizedBox(height: 44),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Page indicators
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: active ? 24 : 8,
                    decoration: BoxDecoration(
                      color: active ? _brandBlue : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
            // CTA button
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: Text(isLast ? 'Mulai Belanja' : 'Lanjut'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String body;

  const _Slide({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.body,
  });
}
