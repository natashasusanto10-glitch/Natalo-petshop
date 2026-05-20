import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// First-launch onboarding 4-slide. Cek di main() via
/// `OnboardingScreen.hasSeen()` untuk decide initial route ('/' vs
/// '/onboarding'). Setelah user complete (Lewati / Mulai di last slide),
/// flag disimpan + navigasi ke '/'.
///
/// Slides:
///   1. Welcome — paw illustration + tagline brand
///   2. Belanja — shopping bag illustration + value prop produk + promo
///   3. Feed — phone reels illustration + community feature
///   4. Notifikasi — bell illustration + push opt-in CTA "Mulai"
///
/// Version key suffix (_v2) — supaya user existing yang sudah lihat
/// onboarding lama (_v1) tetap lihat onboarding baru sekali. Setelah
/// dismiss, tidak akan muncul lagi.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Bump suffix saat ada redesign besar (mis. _v2, _v3) supaya user
  /// existing lihat ulang version baru. _v1 = stub lama 1-page, _v2 =
  /// rewrite 4-page dengan Lottie.
  static const _key = 'onboarding_seen_v2';

  static Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentIndex = 0;

  // Semua slide pakai icon Material + colored circle (2D flat, clean).
  // User report Lottie animations di slide 1 + 4 tidak jelas — frame
  // pertama atau frame di tengah animasi tidak communicate konsep
  // slide dengan jelas. Pakai icon static yang universal recognizable.
  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      icon: Icons.pets_rounded,
      iconColor: Color(0xFF0B7FEA),
      iconBg: Color(0xFFEAF3FF),
      title: 'Selamat datang di Natalo',
      body:
          'Belanja kebutuhan peliharaan jadi lebih mudah, semua ada dalam '
          'satu aplikasi.',
      accentColor: NataloColors.primary,
    ),
    _OnboardingSlide(
      icon: Icons.shopping_bag_rounded,
      iconColor: Color(0xFFF59E0B),
      iconBg: Color(0xFFFFF7E0),
      title: 'Belanja kebutuhan hewan kesayangan',
      body:
          'Makanan, vitamin, mainan, dan perlengkapan lengkap. '
          'Promo & gratis ongkir untuk member.',
      accentColor: Color(0xFFF59E0B),
    ),
    _OnboardingSlide(
      icon: Icons.play_circle_outline_rounded,
      iconColor: Color(0xFFEC4899),
      iconBg: Color(0xFFFCE7F3),
      title: 'Bagikan momen di Feed',
      body:
          'Lihat video komunitas pet lovers, upload momen seru peliharaanmu, '
          'dan dapat inspirasi belanja langsung dari video.',
      accentColor: Color(0xFFEC4899),
    ),
    _OnboardingSlide(
      icon: Icons.notifications_active_rounded,
      iconColor: Color(0xFF22C55E),
      iconBg: Color(0xFFE8F8EF),
      title: 'Aktifkan notifikasi promo & order',
      body:
          'Dapat info promo flash sale, update status pesanan, dan reminder '
          'voucher kedaluwarsa langsung di HP.',
      accentColor: Color(0xFF22C55E),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    AppHaptics.tap();
    await OnboardingScreen.markSeen();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _next() {
    AppHaptics.tap();
    if (_currentIndex >= _slides.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentIndex == _slides.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar — "Lewati" kanan atas (skip ke last slide / langsung
            // dismiss). Hide di last slide karena tombol primary = Mulai.
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedOpacity(
                    opacity: isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: isLast ? null : _finish,
                      child: const Text(
                        'Lewati',
                        style: TextStyle(
                          color: NataloColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            // PageView — swipeable slides.
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  return _OnboardingSlideView(slide: _slides[index]);
                },
              ),
            ),

            // Page indicator dots.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (index) {
                  final active = index == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: active ? 28 : 8,
                    decoration: BoxDecoration(
                      color: active
                          ? NataloColors.primary
                          : const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),

            // Bottom CTA — "Lanjut" di slide 1-3, "Mulai Sekarang" di last.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NataloColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: Text(isLast ? 'Mulai Sekarang' : 'Lanjut'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data class untuk satu slide onboarding — Material icon dengan soft
/// colored circle bg. 2D flat, clean, universal recognizable.
///
/// Note: sebelumnya support optional Lottie animation (lottiePath param),
/// tapi user feedback "Lottie tidak jelas" — frame paw/box animation
/// tidak communicate konsep slide dengan jelas. Switched ke Material
/// icons sepenuhnya untuk semua 4 slide.
class _OnboardingSlide {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String body;
  final Color accentColor;

  const _OnboardingSlide({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.body,
    required this.accentColor,
  });
}

/// Single slide view — icon hero dengan soft colored circle + title + body.
class _OnboardingSlideView extends StatelessWidget {
  final _OnboardingSlide slide;

  const _OnboardingSlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: slide.iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 88,
              color: slide.iconColor,
            ),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NataloColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
