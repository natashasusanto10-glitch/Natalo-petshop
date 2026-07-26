import 'package:flutter/material.dart';

/// Palette warna brand Natalo Petshop. Semua warna yang dipakai di lebih dari
/// satu tempat ditarik ke sini supaya konsisten dan gampang theme-switch.
class NataloColors {
  NataloColors._();

  // ── Base ──
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // ── Brand primary (biru Natalo) ──
  /// Existing Natalo blue. Dipertahankan sebagai primary agar redesign lama
  /// tidak berubah drastis saat sistem warna dirapikan.
  static const Color primary = Color(0xFF1E5FBF);
  static const Color primaryDark = Color(0xFF0B7FEA);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color primarySoft = Color(0xFFEEF4FF);
  static const Color primaryNavy = Color(0xFF1E3A8A);
  static const Color primaryNavyDark = Color(0xFF1E2E6B);
  static const Color accent = Color(0xFFF2A93B);
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color accentSoft = Color(0xFFFFF1EB);
  static const Color accentDark = Color(0xFFE55520);

  // ── Identitas akun official (Natalo Petshop) ──
  // Satu keluarga emas premium dipakai SERAGAM di semua layar (feed,
  // komentar, likers, follow list, profil) untuk nama + centang rosette.
  // [officialGold] untuk latar gelap/hero; [officialGoldOnLight] (lebih
  // pekat) untuk sheet putih supaya tetap terbaca. Gradasi rosette metalik
  // di widget OfficialVerifiedBadge.
  static const Color officialGold = Color(0xFFF3D88E);
  static const Color officialGoldOnLight = Color(0xFFA9781F);
  static const Color officialRosetteTop = Color(0xFFF6E19A);
  static const Color officialRosetteMid = Color(0xFFE3B84C);
  static const Color officialRosetteBottom = Color(0xFFB8862B);

  /// Alias `primary` untuk legacy reference `NataloColors.nataloBlue`.
  static const Color nataloBlue = primary;

  // ── Hero biru (blok header brand — Beranda, Belanja, Transaksi, Akun,
  // Notifikasi) ──
  // Satu sumber untuk gradasi header biru pekat supaya semua halaman serasi;
  // jangan hardcode ulang per screen. Pakai [heroGradient] (header) dan
  // [heroGradientContinue] (strip penutup, mis. trust marquee) — JANGAN
  // menyusun LinearGradient sendiri per halaman.
  // Warna fixed di light & dark mode (header brand tidak ikut theme surface).
  //
  // Palette "Navy Luxe" (premium): navy dalam & tenang, menggantikan royal
  // blue terang lama (#1E5FBF) yang terkesan kurang berkelas.
  static const Color heroTop = Color(0xFF0C2751);
  static const Color heroMid = Color(0xFF153F86);
  static const Color heroBottom = Color(0xFF1E52AE);

  /// Teks/ikon sekunder redup di atas hero (tagline). Untuk teks yang harus
  /// jelas terbaca pakai [onHeroBright].
  static const Color onHeroSubtle = Color(0xFFAEC6EE);

  /// Teks/ikon terang di atas hero — hampir putih, tetap kebiruan.
  static const Color onHeroBright = Color(0xFFEAF1FC);

  /// Chip tidak aktif di atas hero (chip aktif = putih + teks [heroMid]).
  static const Color heroChip = Color(0xFF2C5CA8);

  // Sentuhan premium: arah gradasi sedikit diagonal (≈160°) untuk kedalaman.
  // begin/end dipakai SAMA di semua blok hero supaya garis gradasi paralel —
  // blok yang bertumpuk di Beranda (status → header → marquee) tetap menyatu,
  // tidak ada seam miring.
  static const Alignment heroGradientBegin = Alignment(-0.55, -1.0);
  static const Alignment heroGradientEnd = Alignment(0.55, 1.0);

  /// Gradasi header standar (heroTop→heroMid). Pakai ini di SEMUA header hero
  /// supaya warna + arah identik antar halaman.
  static const LinearGradient heroGradient = LinearGradient(
    begin: heroGradientBegin,
    end: heroGradientEnd,
    colors: [heroTop, heroMid],
  );

  /// Lanjutan gradasi ke bawah (heroMid→heroBottom) — mis. trust marquee
  /// strip Beranda yang menyambung di bawah header sebagai satu blok.
  static const LinearGradient heroGradientContinue = LinearGradient(
    begin: heroGradientBegin,
    end: heroGradientEnd,
    colors: [heroMid, heroBottom],
  );

  // ── Varian VERTIKAL murni (tanpa diagonal) ──
  // Diagonal [heroGradient] memakai Alignment pecahan yang RELATIF ke tinggi
  // tiap kotak → sudut gradasi berubah drastis antar blok yang tingginya beda.
  // Contoh: top bar Akun (56px, sangat lebar-pendek) jadi gradasi ~horizontal,
  // sedangkan blok profil di bawahnya (~300px) jadi ~vertikal → arah gradasi
  // patah di batas = seam "biru tidak menyatu". Vertikal murni (dx=0) adalah
  // satu-satunya arah yang tetap "atas→bawah" di semua tinggi kotak, sehingga
  // blok yang bertumpuk pasti menyatu. Dipakai di Akun & Transaksi; halaman
  // hero lain tetap pakai [heroGradient] diagonal.
  static const Alignment heroVBegin = Alignment(0, -1);
  static const Alignment heroVEnd = Alignment(0, 1);

  /// Gradasi hero vertikal untuk blok atas (status bar + top bar): heroTop→
  /// heroMid. Batas bawah = heroMid supaya sambung mulus dengan
  /// [heroGradientVContinue].
  static const LinearGradient heroGradientV = LinearGradient(
    begin: heroVBegin,
    end: heroVEnd,
    colors: [heroTop, heroMid],
  );

  /// Lanjutan vertikal (heroMid→heroBottom) untuk blok konten hero di bawah
  /// top bar (mis. blok profil Akun). Batas atas = heroMid → menyatu dengan
  /// [heroGradientV].
  static const LinearGradient heroGradientVContinue = LinearGradient(
    begin: heroVBegin,
    end: heroVEnd,
    colors: [heroMid, heroBottom],
  );

  // ── Neutral scale ──
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey300 = Color(0xFFD1D5DB);
  static const Color grey400 = Color(0xFF9CA3AF);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey600 = Color(0xFF4B5563);
  static const Color grey700 = Color(0xFF374151);
  static const Color grey800 = Color(0xFF1F2937);
  static const Color grey900 = Color(0xFF111827);

  // ── Surfaces (light) ──
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color surfaceVariant = grey50;

  /// Alias `border` untuk legacy reference `NataloColors.divider`.
  static const Color divider = border;

  // ── Surfaces (dark) — slightly warm hint-blue tone (less eye strain di OLED) ──
  // Detail audit di DARKMODE_AUDIT.md.
  static const Color backgroundDark = Color(0xFF0A0F1A);
  static const Color surfaceDark = Color(0xFF1A1F2E);
  static const Color surfaceElevatedDark = Color(0xFF1F2937);
  static const Color surfaceVariantDark = Color(0xFF22293A);
  static const Color borderDark = Color(0xFF2A3142);

  // ── Text ──
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);

  /// Alias `textTertiary` untuk legacy reference `NataloColors.textMuted`.
  static const Color textMuted = textTertiary;

  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  // ── Semantic ──
  static const Color success = Color(0xFF22C55E);
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color successDark = Color(0xFF16A34A);

  /// Alias `success` untuk legacy reference `NataloColors.successGreen`.
  static const Color successGreen = success;

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFFFBEB);
  static const Color warningDark = Color(0xFFD97706);

  static const Color danger = Color(0xFFEF4444);
  static const Color dangerSoft = Color(0xFFFEF2F2);
  static const Color dangerDark = Color(0xFFDC2626);

  /// Alias `danger` untuk legacy reference `NataloColors.discountRed`.
  static const Color discountRed = danger;

  /// Merah hati "disukai" di feed — rail like, burst double-tap, dan badge.
  /// SATU sumber: sebelumnya hex 0xFFEF4444 diulang di feed_action_rail,
  /// feed_post_shared_widgets, feed_screen, dan gallery_post_tile (rawan
  /// drift). Dinamai terpisah dari `danger` karena perannya semantik beda
  /// (afeksi, bukan galat) sehingga bisa berdivergensi tanpa menyentuh
  /// warna error di seluruh app.
  static const Color likeRed = danger;

  static const Color info = Color(0xFF3B82F6);
  static const Color infoSoft = Color(0xFFEFF6FF);
  static const Color infoDark = Color(0xFF2563EB);

  /// Ungu "dalam perjalanan" — status pesanan DIKIRIM/SHIPPED.
  ///
  /// Perlu hue sendiri karena semua warna status lain sudah terpakai: menunggu
  /// bayar = [warning], diproses & siap ambil = [primary], selesai =
  /// [success], dibatalkan = [danger]. Tanpa ungu, "dikirim" akan menumpuk
  /// warna dengan "diproses" padahal itu dua tahap berbeda di timeline.
  ///
  /// SATU sumber: sebelumnya hub Transaksi dan halaman detail memakai warna
  /// TERTUKAR untuk status yang sama (hub: dikirim hijau/selesai ungu; detail:
  /// dikirim ungu/selesai hijau).
  static const Color shipping = Color(0xFF7C3AED);
  static const Color shippingSoft = Color(0xFFF3E8FF);

  // ── Brand-exclusive (aksen amber "Brand Eksklusif") ──
  // Satu sumber untuk palet voucher/badge brand-exclusive — dipakai di badge
  // grid produk, chip voucher detail/cart/checkout, dan pill member vouchers.
  // Jangan hardcode ulang per screen: rebrand cukup ubah di sini.
  /// Fill solid amber terang untuk ikon "workspace premium" (mis. kontainer
  /// ikon voucher brand di detail produk).
  static const Color brandExclusive = Color(0xFFF7A100);

  /// Latar chip/pill "Brand Eksklusif" (soft).
  static const Color brandExclusiveSoft = Color(0xFFFEF0DC);

  /// Border chip/pill "Brand Eksklusif" (soft).
  static const Color brandExclusiveBorder = Color(0xFFFCD9A0);

  /// Teks & ikon gelap "Brand Eksklusif" (kontras di atas [brandExclusiveSoft]).
  static const Color brandExclusiveDark = Color(0xFFB85C00);

  // ── Category colors ──
  static const Color catKucingBg = primarySoft;
  static const Color catKucingIcon = primaryNavy;
  static const Color catAnjingBg = Color(0xFFFFF7E6);
  static const Color catAnjingIcon = warningDark;
  static const Color catPasirBg = Color(0xFFF3F4F6);
  static const Color catPasirIcon = grey500;
  static const Color catVitaminBg = Color(0xFFFFE4E6);
  static const Color catVitaminIcon = Color(0xFFE11D48);
  static const Color catVoucherBg = Color(0xFFFCE7F3);
  static const Color catVoucherIcon = Color(0xFFBE185D);
  static const Color catPoinBg = warningSoft;
  static const Color catPoinIcon = warningDark;
  static const Color catGroomingBg = successSoft;
  static const Color catGroomingIcon = success;
  static const Color catBlogBg = Color(0xFFFEF3C7);
  static const Color catBlogIcon = Color(0xFF92400E);

  // ── Legacy soft aliases ──
  static const Color softBlue = primarySoft;
  static const Color softCyan = Color(0xFFEAFBFF);
  static const Color softMint = successSoft;

  // ── Price / e-commerce semantic ──
  /// Warna utama harga produk (sama dengan `textPrimary` untuk konsistensi).
  static const Color priceText = textPrimary;

  /// Warna harga coret (lebih muted, untuk old price strikethrough).
  static const Color oldPriceText = textTertiary;

  // ── Feed (immersive black) ──
  static const Color feedBlack = Color(0xFF000000);
  static const Color feedOverlay = Color(0xCC000000);

  /// Alias `feedBlack` — beberapa code pakai `feedDark`.
  static const Color feedDark = feedBlack;

  /// Muted text di feed (dark theme reels).
  static const Color feedTextMuted = Color(0xFFB0B7C3);
}

class NataloTextStyles {
  const NataloTextStyles._();

  static const TextStyle productPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static const TextStyle productDetailPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.3,
  );

  static const TextStyle cartPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static const TextStyle totalPaymentPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static const TextStyle oldPrice = TextStyle(
    color: NataloColors.oldPriceText,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.lineThrough,
  );

  static const TextStyle discountText = TextStyle(
    color: NataloColors.discountRed,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle freeShippingText = TextStyle(
    color: NataloColors.successGreen,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
}
