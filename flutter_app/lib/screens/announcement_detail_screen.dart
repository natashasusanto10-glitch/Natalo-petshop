import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _primaryDark = Color(0xFF075CB5);
const _primaryLight = Color(0xFFEAF5FF);

/// **Detail Pengumuman** screen — match Capacitor pattern:
/// - AppBar back arrow + "Detail Pengumuman" w900 left-aligned (no centerTitle)
/// - Card radius 18: megaphone icon dalam rounded-square light-blue + title
///   besar w900 (wrap 2 lines) + decorative dots di pojok atas + meta row
///   primary (jam relative + date absolute) + info box light-blue + divider
///   center paw icon + body + signature "Natalo Petshop" w800
/// - Bottom solid pill button "✓ Mengerti" (close screen)
class AnnouncementDetailScreen extends StatelessWidget {
  final AppNotification notification;

  const AnnouncementDetailScreen({super.key, required this.notification});

  // Date helpers ada di utils/formatters.dart (single source untuk semua
  // date display di app). Sebelumnya inline di sini, sekarang centralized.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0xFFF8FAFC),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF17202A),
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        // Left-aligned w900 title (NOT centered) — match Capacitor pattern
        // untuk content screens (beda dari auth screens yang centered).
        title: const Text(
          'Detail Pengumuman',
          style: TextStyle(
            color: Color(0xFF17202A),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── Main announcement card ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top section: icon + title + decorative dots ──
                  Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Megaphone icon dalam rounded-square light-blue
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _primaryLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.campaign_rounded,
                              color: _brandBlue,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Title w900 ~22 (2 lines max)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2, right: 28),
                              child: Text(
                                notification.title,
                                maxLines: 3,
                                style: const TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Decorative dots di pojok kanan atas
                      const Positioned(
                        top: 4,
                        right: 0,
                        child: _DecorativeDots(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // ── Meta row: relative time + absolute date ──
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _MetaItem(
                        icon: Icons.access_time_rounded,
                        text: formatRelativeTime(notification.createdAt),
                      ),
                      Container(
                        height: 12,
                        width: 1,
                        color: const Color(0xFFE5E7EB),
                      ),
                      _MetaItem(
                        icon: Icons.calendar_today_outlined,
                        text: formatDateTime(notification.createdAt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Info box light-blue dengan info icon + body ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _primaryLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.info_outline_rounded,
                            color: _brandBlue,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            notification.body,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ── Divider dengan center paw icon ──
                  Row(
                    children: [
                      const Expanded(
                        child: Divider(color: Color(0xFFE5E7EB), height: 1),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: _primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.pets_rounded,
                          color: _brandBlue,
                          size: 16,
                        ),
                      ),
                      const Expanded(
                        child: Divider(color: Color(0xFFE5E7EB), height: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Closing message + signature ──
                  const Text(
                    'Terima kasih atas perhatian dan kerjasamanya.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Natalo Petshop',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ── Solid pill button "Mengerti" ──
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () {
                AppHaptics.tap();
                Navigator.maybePop(context);
              },
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text(
                'Mengerti',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative dots di pojok kanan atas card — visual flair match Capacitor.
class _DecorativeDots extends StatelessWidget {
  const _DecorativeDots();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          Positioned(
            top: 6,
            right: 4,
            child: _Dot(size: 6, color: _brandBlue.withValues(alpha: 0.18)),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: _Dot(
              size: 4,
              color: const Color(0xFFF59E0B).withValues(alpha: 0.65),
            ),
          ),
          Positioned(
            top: 2,
            right: 22,
            child: _Dot(size: 3, color: _primaryDark.withValues(alpha: 0.4)),
          ),
          Positioned(
            top: 28,
            right: 8,
            child: _Dot(size: 5, color: _brandBlue.withValues(alpha: 0.10)),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final Color color;
  const _Dot({required this.size, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Meta item icon + text (jam relative / date absolute) — pakai primary color.
class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _brandBlue, size: 14),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: _brandBlue,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
