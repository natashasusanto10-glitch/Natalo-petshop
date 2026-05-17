import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_ui.dart';
import '../widgets/glass_surface.dart';

const _brandBlue = Color(0xFF0B7FEA);

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  Future<void> _openUri(BuildContext context, String value) async {
    final uri = Uri.parse(value);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tidak bisa membuka aplikasi tujuan.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Bantuan'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'FAQ'),
              Tab(text: 'Order'),
              Tab(text: 'Tentang'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FaqTab(onOpenUri: (value) => _openUri(context, value)),
            const _OrderGuideTab(),
            _AboutTab(onOpenUri: (value) => _openUri(context, value)),
          ],
        ),
      ),
    );
  }
}

class _FaqTab extends StatelessWidget {
  final ValueChanged<String> onOpenUri;

  const _FaqTab({required this.onOpenUri});

  static const _items = [
    _FaqItem(
      question: 'Bagaimana cara order di Natalo Petshop?',
      answer:
          'Pilih produk, tambah ke keranjang, buka checkout, pilih alamat pengiriman, pilih kurir dan metode pembayaran, lalu buat pesanan.',
      icon: Icons.shopping_bag_outlined,
    ),
    _FaqItem(
      question: 'Berapa lama pengiriman?',
      answer:
          'Area Medan bisa memakai Natalo Instant 1-3 jam saat jam operasional. Pengiriman nasional mengikuti estimasi kurir yang dipilih.',
      icon: Icons.local_shipping_outlined,
    ),
    _FaqItem(
      question: 'Apa metode pembayaran yang tersedia?',
      answer:
          'Transfer manual dan Midtrans. Midtrans dapat mendukung VA, QRIS, kartu, dan e-wallet sesuai kanal yang aktif di backend.',
      icon: Icons.payments_outlined,
    ),
    _FaqItem(
      question: 'Bagaimana cek status pesanan?',
      answer:
          'Login member, buka Akun, lalu Pesanan Saya. Detail order menampilkan status pembayaran, pengiriman, dan item pesanan.',
      icon: Icons.receipt_long_outlined,
    ),
    _FaqItem(
      question: 'Bisa return kalau produk salah atau rusak?',
      answer:
          'Bisa. Hubungi customer service maksimal 1x24 jam setelah paket diterima dan sertakan foto produk serta nomor order.',
      icon: Icons.assignment_return_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const _HelpHero(
          icon: Icons.support_agent_rounded,
          title: 'Pusat Bantuan Natalo',
          body: 'FAQ, panduan order, kontak toko, dan info layanan member.',
        ),
        const SizedBox(height: 14),
        ..._items.indexed.map((entry) {
          final item = entry.$2;
          return AppAnimatedEntrance(
            index: entry.$1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassSurface(
                radius: 24,
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  leading: SoftIconTile(icon: item.icon, size: 42),
                  title: Text(
                    item.question,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.answer,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        _ContactCard(onOpenUri: onOpenUri),
      ],
    );
  }
}

class _OrderGuideTab extends StatelessWidget {
  const _OrderGuideTab();

  static const _steps = [
    ('1', 'Pilih Produk', 'Cari produk dari katalog atau brand favorit.'),
    ('2', 'Tambah Keranjang', 'Cek jumlah, harga, dan stok sebelum checkout.'),
    ('3', 'Pilih Alamat', 'Gunakan alamat member atau tambah alamat baru.'),
    (
      '4',
      'Pilih Pengiriman',
      'Ambil sendiri, Natalo Instant, atau kurir lain.'
    ),
    ('5', 'Bayar Pesanan', 'Pilih transfer manual atau Midtrans.'),
    ('6', 'Pantau Status', 'Buka Pesanan Saya untuk update order.'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: _steps.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _HelpHero(
            icon: Icons.route_rounded,
            title: 'Cara Pemesanan',
            body:
                'Alur belanja dibuat sama seperti app Capacitor: cepat, jelas, dan bisa dipantau dari akun member.',
          );
        }
        final step = _steps[index - 1];
        return AppAnimatedEntrance(
          index: index,
          child: GlassSurface(
            radius: 24,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFEAF5FF),
                  child: Text(
                    step.$1,
                    style: const TextStyle(
                      color: _brandBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.$2,
                        style: const TextStyle(
                          color: Color(0xFF17202A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.$3,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AboutTab extends StatelessWidget {
  final ValueChanged<String> onOpenUri;

  const _AboutTab({required this.onOpenUri});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const _HelpHero(
          icon: Icons.storefront_rounded,
          title: 'Natalo Petshop & Aquarium',
          body:
              'Toko hewan peliharaan terpercaya di Medan untuk kucing, anjing, ikan hias, dan kebutuhan petcare.',
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: _StatCard(value: '2.200+', label: 'Produk')),
            SizedBox(width: 10),
            Expanded(child: _StatCard(value: '7+', label: 'Tahun')),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(child: _StatCard(value: '100+', label: 'Brand')),
            SizedBox(width: 10),
            Expanded(child: _StatCard(value: '10k+', label: 'Pelanggan')),
          ],
        ),
        const SizedBox(height: 14),
        const _CommitmentCard(
          icon: Icons.verified_user_outlined,
          title: 'Produk original',
          body: 'Produk bersumber dari distributor resmi dan brand terpercaya.',
        ),
        const _CommitmentCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Konsultasi gratis',
          body: 'Tim Natalo siap bantu pilih produk sesuai kebutuhan hewan.',
        ),
        const _CommitmentCard(
          icon: Icons.assignment_return_outlined,
          title: 'Garansi komplain',
          body: 'Komplain produk salah/rusak bisa diajukan maksimal 1x24 jam.',
        ),
        const SizedBox(height: 6),
        _ContactCard(onOpenUri: onOpenUri),
      ],
    );
  }
}

class _HelpHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _HelpHero({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 30,
      tint: const Color(0xFFF8FCFF),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SoftIconTile(icon: icon, size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF17202A),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ValueChanged<String> onOpenUri;

  const _ContactCard({required this.onOpenUri});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 26,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hubungi Natalo',
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _ContactTile(
            icon: Icons.location_on_outlined,
            title: 'Alamat',
            subtitle: 'Jl. MT. Haryono No. 103 BCD, Medan',
            onTap: () =>
                onOpenUri('https://maps.google.com/?q=Natalo+Petshop+Medan'),
          ),
          _ContactTile(
            icon: Icons.phone_in_talk_outlined,
            title: 'WhatsApp',
            subtitle: '+62 812 8999 7113',
            onTap: () => onOpenUri('https://wa.me/6281289997113'),
          ),
          _ContactTile(
            icon: Icons.mail_outline_rounded,
            title: 'Email',
            subtitle: 'natalopetshop@gmail.com',
            onTap: () => onOpenUri('mailto:natalopetshop@gmail.com'),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SoftIconTile(icon: icon, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _brandBlue,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitmentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _CommitmentCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassSurface(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SoftIconTile(icon: icon, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;
  final IconData icon;

  const _FaqItem({
    required this.question,
    required this.answer,
    required this.icon,
  });
}
