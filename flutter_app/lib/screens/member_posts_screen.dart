import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Postingan Saya — daftar video feed yang user upload.
class MemberPostsScreen extends StatelessWidget {
  const MemberPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Postingan Saya'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.video_collection_outlined,
                  size: 44,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Belum ada postingan',
                style: TextStyle(
                  color: NataloColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bagikan momen seru bersama hewan peliharaan Anda di Feed Natalo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NataloColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/feed'),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Buat Postingan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
