import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

class StaticInfoScreen extends StatelessWidget {
  final _StaticInfoPage _page;

  const StaticInfoScreen.accountPrivacy({super.key})
      : _page = _accountPrivacyPage;

  const StaticInfoScreen.about({super.key}) : _page = _aboutPage;

  const StaticInfoScreen.orderGuide({super.key}) : _page = _orderGuidePage;

  const StaticInfoScreen.terms({super.key}) : _page = _termsPage;

  const StaticInfoScreen.privacyPolicy({super.key}) : _page = _privacyPage;

  const StaticInfoScreen.returnPolicy({super.key}) : _page = _returnPage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: Text(_page.title),
        backgroundColor: const Color(0xFFF7FAFF),
        surfaceTintColor: const Color(0xFFF7FAFF),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _InfoHero(page: _page),
          const SizedBox(height: 18),
          for (final section in _page.sections) ...[
            _SectionLabel(section.title),
            const SizedBox(height: 8),
            _InfoSectionCard(section: section),
            const SizedBox(height: 16),
          ],
          if (_page.note != null) _InfoNote(text: _page.note!),
        ],
      ),
    );
  }
}

class _InfoHero extends StatelessWidget {
  final _StaticInfoPage page;

  const _InfoHero({required this.page});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [NataloColors.primary, NataloColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: NataloColors.primary.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Icon(page.icon, color: Colors.white, size: 29),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  page.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
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

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: NataloColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _InfoSectionCard extends StatelessWidget {
  final _StaticInfoSection section;

  const _InfoSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8F8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < section.items.length; i++) ...[
            _InfoItemTile(item: section.items[i]),
            if (i != section.items.length - 1)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Color(0xFFE8EEF7),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoItemTile extends StatelessWidget {
  final _StaticInfoItem item;

  const _InfoItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: NataloColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: NataloColors.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: const TextStyle(
                    color: NataloColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
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

class _InfoNote extends StatelessWidget {
  final String text;

  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NataloColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E7FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: NataloColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticInfoPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<_StaticInfoSection> sections;
  final String? note;

  const _StaticInfoPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sections,
    this.note,
  });
}

class _StaticInfoSection {
  final String title;
  final List<_StaticInfoItem> items;

  const _StaticInfoSection({
    required this.title,
    required this.items,
  });
}

class _StaticInfoItem {
  final IconData icon;
  final String title;
  final String body;

  const _StaticInfoItem({
    required this.icon,
    required this.title,
    required this.body,
  });
}

const _accountPrivacyPage = _StaticInfoPage(
  title: 'Privasi Akun',
  subtitle:
      'Kontrol data akun, keamanan, notifikasi, dan preferensi member Natalo.',
  icon: Icons.privacy_tip_outlined,
  sections: [
    _StaticInfoSection(
      title: 'DATA AKUN',
      items: [
        _StaticInfoItem(
          icon: Icons.badge_outlined,
          title: 'Data profil',
          body:
              'Nama, email, nomor HP, dan foto profil dipakai untuk identitas member, pesanan, voucher, dan bantuan customer service.',
        ),
        _StaticInfoItem(
          icon: Icons.location_on_outlined,
          title: 'Alamat tersimpan',
          body:
              'Alamat hanya dipakai untuk pengiriman, estimasi ongkir, dan mempercepat checkout berikutnya.',
        ),
        _StaticInfoItem(
          icon: Icons.receipt_long_outlined,
          title: 'Aktivitas belanja',
          body:
              'Riwayat pesanan, wishlist, voucher, dan poin member tersimpan di akun agar benefit tetap mengikuti akun kamu.',
        ),
      ],
    ),
    _StaticInfoSection(
      title: 'KONTROL PRIVASI',
      items: [
        _StaticInfoItem(
          icon: Icons.notifications_none_rounded,
          title: 'Preferensi notifikasi',
          body:
              'Kamu bisa mengatur notifikasi pesanan, promo, feed, dan pengumuman dari menu Notifikasi.',
        ),
        _StaticInfoItem(
          icon: Icons.lock_outline_rounded,
          title: 'Keamanan akun',
          body:
              'Gunakan menu Keamanan Akun untuk reset password, kunci aplikasi, logout perangkat lain, atau mengajukan hapus akun.',
        ),
      ],
    ),
  ],
  note:
      'Natalo tidak menampilkan data pribadi kamu ke pengguna lain tanpa kebutuhan layanan atau persetujuan kamu.',
);

const _aboutPage = _StaticInfoPage(
  title: 'Tentang Natalo',
  subtitle:
      'Natalo Petshop membantu member membeli kebutuhan hewan dengan produk original, layanan rapi, dan benefit member.',
  icon: Icons.pets_rounded,
  sections: [
    _StaticInfoSection(
      title: 'NATALO PETSHOP',
      items: [
        _StaticInfoItem(
          icon: Icons.storefront_rounded,
          title: 'Petshop untuk kebutuhan harian',
          body:
              'Kami menyediakan makanan, vitamin, pasir, aquarium, dan perlengkapan hewan peliharaan.',
        ),
        _StaticInfoItem(
          icon: Icons.verified_rounded,
          title: 'Produk original',
          body:
              'Produk disiapkan dari katalog resmi Natalo dan diperiksa sebelum masuk ke proses pengiriman.',
        ),
        _StaticInfoItem(
          icon: Icons.card_giftcard_rounded,
          title: 'Benefit member',
          body:
              'Member bisa menyimpan alamat, melihat pesanan, mengumpulkan poin, memakai voucher, dan menyimpan wishlist.',
        ),
      ],
    ),
    _StaticInfoSection(
      title: 'LAYANAN',
      items: [
        _StaticInfoItem(
          icon: Icons.local_shipping_outlined,
          title: 'Pengiriman dan pickup',
          body:
              'Pilih pengiriman sesuai alamat atau ambil sendiri di toko jika metode tersebut tersedia.',
        ),
        _StaticInfoItem(
          icon: Icons.support_agent_rounded,
          title: 'Bantuan customer service',
          body:
              'Tim Natalo siap membantu pertanyaan produk, pesanan, pembayaran, dan pengiriman.',
        ),
      ],
    ),
  ],
);

const _orderGuidePage = _StaticInfoPage(
  title: 'Cara Pemesanan',
  subtitle:
      'Ikuti langkah singkat ini untuk membuat pesanan dari aplikasi Natalo.',
  icon: Icons.checklist_rounded,
  sections: [
    _StaticInfoSection(
      title: 'LANGKAH ORDER',
      items: [
        _StaticInfoItem(
          icon: Icons.search_rounded,
          title: 'Cari produk',
          body:
              'Buka Beranda atau Produk, lalu cari makanan, vitamin, pasir, atau perlengkapan yang kamu butuhkan.',
        ),
        _StaticInfoItem(
          icon: Icons.shopping_cart_outlined,
          title: 'Masukkan ke keranjang',
          body:
              'Cek jumlah barang di Keranjang. Jika jumlah melebihi stok, sistem mengikuti stok tersedia.',
        ),
        _StaticInfoItem(
          icon: Icons.local_shipping_outlined,
          title: 'Checkout',
          body:
              'Pilih alamat, metode pengiriman atau pickup, voucher, catatan, dan metode pembayaran.',
        ),
        _StaticInfoItem(
          icon: Icons.payments_outlined,
          title: 'Selesaikan pembayaran',
          body:
              'Ikuti instruksi pembayaran. Pesanan akan masuk ke Pesanan Saya untuk dipantau.',
        ),
      ],
    ),
    _StaticInfoSection(
      title: 'SETELAH ORDER',
      items: [
        _StaticInfoItem(
          icon: Icons.inventory_2_outlined,
          title: 'Pesanan diproses',
          body:
              'Admin akan memeriksa pembayaran dan menyiapkan barang sesuai stok serta metode pengiriman.',
        ),
        _StaticInfoItem(
          icon: Icons.notifications_active_outlined,
          title: 'Pantau status',
          body:
              'Status pesanan dan notifikasi bisa dilihat dari halaman Akun dan Pusat Notifikasi.',
        ),
      ],
    ),
  ],
);

const _termsPage = _StaticInfoPage(
  title: 'Syarat & Ketentuan',
  subtitle:
      'Ketentuan penggunaan aplikasi, transaksi, voucher, dan layanan Natalo.',
  icon: Icons.description_outlined,
  sections: [
    _StaticInfoSection(
      title: 'PENGGUNAAN AKUN',
      items: [
        _StaticInfoItem(
          icon: Icons.person_outline_rounded,
          title: 'Akun member',
          body:
              'Pengguna bertanggung jawab menjaga email, nomor HP, password, dan aktivitas yang terjadi di akun.',
        ),
        _StaticInfoItem(
          icon: Icons.shield_outlined,
          title: 'Keamanan',
          body:
              'Natalo dapat membatasi aktivitas yang terindikasi penyalahgunaan, spam, atau pelanggaran aturan aplikasi.',
        ),
      ],
    ),
    _StaticInfoSection(
      title: 'TRANSAKSI',
      items: [
        _StaticInfoItem(
          icon: Icons.inventory_2_outlined,
          title: 'Stok dan harga',
          body:
              'Stok, harga, voucher, dan promo dapat berubah mengikuti data terbaru di sistem Natalo.',
        ),
        _StaticInfoItem(
          icon: Icons.confirmation_number_outlined,
          title: 'Voucher',
          body:
              'Voucher hanya berlaku jika memenuhi syarat transaksi, masa aktif, kuota, dan limit pemakaian.',
        ),
        _StaticInfoItem(
          icon: Icons.receipt_long_outlined,
          title: 'Pesanan',
          body:
              'Pesanan diproses setelah pembayaran valid atau sesuai prosedur metode pembayaran yang dipilih.',
        ),
      ],
    ),
  ],
);

const _privacyPage = _StaticInfoPage(
  title: 'Kebijakan Privasi',
  subtitle:
      'Ringkasan cara Natalo mengumpulkan, memakai, dan menjaga data pengguna.',
  icon: Icons.privacy_tip_outlined,
  sections: [
    _StaticInfoSection(
      title: 'DATA YANG DIPAKAI',
      items: [
        _StaticInfoItem(
          icon: Icons.badge_outlined,
          title: 'Identitas member',
          body:
              'Nama, email, nomor HP, foto profil, dan alamat diperlukan untuk login, checkout, pengiriman, dan bantuan.',
        ),
        _StaticInfoItem(
          icon: Icons.shopping_bag_outlined,
          title: 'Aktivitas transaksi',
          body:
              'Data keranjang, pesanan, voucher, poin, wishlist, dan ulasan dipakai untuk menjalankan layanan aplikasi.',
        ),
        _StaticInfoItem(
          icon: Icons.notifications_none_rounded,
          title: 'Notifikasi',
          body:
              'Token notifikasi dipakai untuk mengirim update pesanan, promo, feed, dan pengumuman sesuai preferensi.',
        ),
      ],
    ),
    _StaticInfoSection(
      title: 'KEAMANAN DATA',
      items: [
        _StaticInfoItem(
          icon: Icons.lock_outline_rounded,
          title: 'Perlindungan akses',
          body:
              'Data akun dilindungi melalui autentikasi akun dan kontrol akses pada sistem Natalo.',
        ),
        _StaticInfoItem(
          icon: Icons.tune_rounded,
          title: 'Kontrol pengguna',
          body:
              'Kamu dapat mengubah profil, alamat, preferensi notifikasi, dan mengajukan penghapusan akun melalui menu akun.',
        ),
      ],
    ),
  ],
);

const _returnPage = _StaticInfoPage(
  title: 'Kebijakan Pengembalian',
  subtitle:
      'Panduan retur, refund, dan pengecekan produk setelah pesanan diterima.',
  icon: Icons.assignment_return_outlined,
  sections: [
    _StaticInfoSection(
      title: 'SYARAT RETUR',
      items: [
        _StaticInfoItem(
          icon: Icons.inventory_2_outlined,
          title: 'Produk bermasalah',
          body:
              'Ajukan bantuan jika produk rusak, salah kirim, atau tidak sesuai pesanan saat diterima.',
        ),
        _StaticInfoItem(
          icon: Icons.photo_camera_outlined,
          title: 'Bukti pendukung',
          body:
              'Siapkan foto atau video paket, produk, label pengiriman, dan nomor pesanan untuk proses pengecekan.',
        ),
        _StaticInfoItem(
          icon: Icons.timer_outlined,
          title: 'Batas laporan',
          body:
              'Laporkan kendala secepatnya setelah barang diterima agar tim Natalo bisa membantu verifikasi.',
        ),
      ],
    ),
    _StaticInfoSection(
      title: 'PROSES',
      items: [
        _StaticInfoItem(
          icon: Icons.support_agent_rounded,
          title: 'Hubungi customer service',
          body:
              'Tim Natalo akan memeriksa bukti, kondisi produk, dan status pesanan sebelum menentukan solusi.',
        ),
        _StaticInfoItem(
          icon: Icons.payments_outlined,
          title: 'Refund atau penggantian',
          body:
              'Jika pengajuan disetujui, solusi dapat berupa penggantian produk, voucher, atau refund sesuai kasus.',
        ),
      ],
    ),
  ],
  note:
      'Produk yang sudah dibuka, dipakai, atau rusak karena penyimpanan setelah diterima dapat tidak memenuhi syarat retur.',
);
