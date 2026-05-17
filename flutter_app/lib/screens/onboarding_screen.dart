import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/natalo_colors.dart';

/// First-launch onboarding. Cek di main() via `OnboardingScreen.hasSeen()`
/// untuk decide initial route ('/' vs '/onboarding'). Setelah user tap
/// "Mulai", flag disimpan + navigasi ke '/'.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const _key = 'onboarding_seen_v1';

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

  Future<void> _continue(BuildContext context) async {
    await markSeen();
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),
              const Icon(
                Icons.pets_rounded,
                size: 88,
                color: NataloColors.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Selamat datang di Natalo Petshop',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Belanja kebutuhan peliharaan jadi lebih mudah, '
                'dengan promo + delivery cepat ke rumah Anda.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _continue(context),
                child: const Text('Mulai'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
