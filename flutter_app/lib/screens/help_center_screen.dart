import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/natalo_store_config.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Pusat Bantuan — FAQ + kontak customer service (WhatsApp, email).
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pusat Bantuan'),
        backgroundColor: isDark ? cs.surface : const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero: butuh bantuan?
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  NataloColors.primary,
                  NataloColors.primaryLight,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 44,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Butuh bantuan?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tim Natalo siap bantu via WhatsApp & email.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Kontak
          const _SectionLabel('Kontak Natalo'),
          _ContactCard(
            icon: Icons.chat_rounded,
            iconColor: const Color(0xFF16A34A),
            iconBg: const Color(0xFFD1FAE5),
            title: 'WhatsApp',
            subtitle: NataloStoreConfig.whatsappDisplay,
            onTap: () => _openWhatsApp(context),
          ),
          const SizedBox(height: 10),
          _ContactCard(
            icon: Icons.mail_outline_rounded,
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFEDE9FE),
            title: 'Email',
            subtitle: NataloStoreConfig.email,
            onTap: () => _openEmail(context),
          ),
          const SizedBox(height: 10),
          _ContactCard(
            icon: Icons.storefront_rounded,
            iconColor: const Color(0xFFEC4899),
            iconBg: const Color(0xFFFCE7F3),
            title: 'Lokasi Toko',
            subtitle: NataloStoreConfig.address,
            onTap: () => _openMaps(context),
          ),
          const SizedBox(height: 20),
          // FAQ
          const _SectionLabel('Pertanyaan Umum'),
          const _FaqItem(
            question: 'Bagaimana cara pesan produk?',
            answer:
                'Pilih produk → tambah ke keranjang → checkout → pilih pembayaran. Pesanan diproses 1×24 jam (kecuali Minggu & libur).',
          ),
          const _FaqItem(
            question: 'Berapa lama waktu pengiriman?',
            answer:
                'Dalam kota Medan: 1-2 hari. Luar kota: 2-5 hari kerja via JNE/J&T. Self-pickup di toko: gratis ongkir, ambil setelah konfirmasi siap.',
          ),
          const _FaqItem(
            question: 'Apakah produk bergaransi original?',
            answer:
                'Ya, semua produk Natalo 100% original dari distributor resmi. Garansi rusak diganti baru dalam 7 hari setelah barang sampai.',
          ),
          const _FaqItem(
            question: 'Bagaimana cara tukar poin loyalty?',
            answer:
                'Buka Akun → Tukar Poin. Setiap belanja Rp20.000 = 1 poin. Tukar poin jadi voucher mulai dari 20 poin (Rp10.000, min belanja Rp150.000) sampai 200 poin (Rp150.000, min belanja Rp1.500.000).',
          ),
          const _FaqItem(
            question: 'Apakah bisa konsultasi hewan peliharaan?',
            answer:
                'Bisa! Hubungi WhatsApp kami untuk konsultasi gratis seputar makanan, vitamin, atau perawatan hewan peliharaan.',
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'Jam operasional: Senin-Sabtu 09.00-21.00 WIB',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    AppHaptics.tap();
    final uri = NataloStoreConfig.whatsappUri();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        AppToast.show(
          context,
          'Tidak bisa buka WhatsApp. Pastikan WhatsApp terpasang.',
          kind: ToastKind.error,
        );
      }
    }
  }

  Future<void> _openEmail(BuildContext context) async {
    AppHaptics.tap();
    final uri = Uri.parse(
      'mailto:${NataloStoreConfig.email}?subject=Bantuan%20dari%20App',
    );
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        AppToast.show(
          context,
          'Tidak bisa buka aplikasi email.',
          kind: ToastKind.error,
        );
      }
    }
  }

  Future<void> _openMaps(BuildContext context) async {
    AppHaptics.tap();
    final uri = Uri.parse(NataloStoreConfig.mapsUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        AppToast.show(
          context,
          'Tidak bisa buka Google Maps.',
          kind: ToastKind.error,
        );
      }
    }
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

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFDDE8F8),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

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
      child: ExpansionTile(
        shape: const Border(),
        title: Text(
          question,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconColor: NataloColors.primary,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              answer,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
