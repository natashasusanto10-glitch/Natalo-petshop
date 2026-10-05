import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/haptics.dart';

/// Native destination for the admin-managed Kawan Setia launch popup.
class KawanSetiaScreen extends StatefulWidget {
  static const routeName = '/services/kawan-setia';

  const KawanSetiaScreen({super.key, this.openWhatsApp});

  /// Injectable launcher for testing without opening an external application.
  final Future<bool> Function(Uri)? openWhatsApp;

  static Uri get whatsappUri => Uri.https('wa.me', '/6281330003880', {
        'text': 'Halo Kawan Setia, saya melihat layanan di aplikasi Natalo. '
            'Saya ingin bertanya tentang layanan untuk anjing saya.',
      });

  @override
  State<KawanSetiaScreen> createState() => _KawanSetiaScreenState();
}

class _KawanSetiaScreenState extends State<KawanSetiaScreen> {
  static const _cream = Color(0xFFFFFBF2);
  static const _ink = Color(0xFF172B4D);
  static const _green = Color(0xFF168451);
  bool _opening = false;

  Future<void> _contact() async {
    if (_opening) return;
    AppHaptics.tap();
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await (widget.openWhatsApp ??
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication))(
        KawanSetiaScreen.whatsappUri,
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('WhatsApp belum bisa dibuka. Silakan coba lagi.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Kawan Setia'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/kawan-setia-hero.jpg',
                    fit: BoxFit.contain,
                    semanticLabel:
                        'Kawan Setia, dengan anjing kecil, sedang, dan besar',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Yuk, kenali layanan kami',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                    color: _ink, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Text('Untuk anjing kesayanganmu.',
                            style: TextStyle(color: _ink, fontSize: 15)),
                        const SizedBox(height: 20),
                        const _ServiceTile(
                          icon: Icons.bathtub_outlined,
                          title: 'Mandi & Perawatan',
                          description: 'Biar bersih, wangi, dan nyaman.',
                        ),
                        const _ServiceTile(
                          icon: Icons.favorite_outline,
                          title: 'Jasa Pacak Anjing',
                          description: 'Tanyakan pasangan yang tersedia.',
                        ),
                        const _ServiceTile(
                          icon: Icons.directions_walk_rounded,
                          title: 'Jalan-Jalan Anjing',
                          description: 'Teman jalan agar aktif dan ceria.',
                        ),
                        const _ServiceTile(
                          icon: Icons.school_outlined,
                          title: 'Latihan Anjing',
                          description:
                              'Belajar duduk, diam, dan datang saat dipanggil.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Mau tanya layanan atau jadwal?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _ink)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('kawan-setia-whatsapp'),
                      onPressed: _opening ? null : _contact,
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                      icon: SvgPicture.asset(
                        'assets/icons/whatsapp.svg',
                        width: 24,
                        height: 24,
                        excludeFromSemantics: true,
                      ),
                      label: Text(
                          _opening ? 'Membuka WhatsApp…' : 'Tanya via WhatsApp',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile(
      {required this.icon, required this.title, required this.description});
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0EBDD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              backgroundColor: const Color(0xFFFFF2CF),
              foregroundColor: const Color(0xFF172B4D),
              child: Icon(icon),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Color(0xFF172B4D),
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(description,
                    style: const TextStyle(
                        color: Color(0xFF526078), fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
