import 'dart:ui';

import 'package:flutter/material.dart';

import '../state/bottom_nav_scroll.dart';
import '../state/member_store.dart';
import '../theme/natalo_colors.dart';
import 'profile_avatar.dart';

/// Bottom nav bar Natalo: floating glass pill, gaya premium IG/Material 3.
///
/// Index urutan:
///  0 = Beranda    /
///  1 = Produk     /products
///  2 = Feed       /feed
///  3 = Transaksi  /transactions
///  4 = Akun       /member
///
/// **Desain (Arah 1 + Gaya C):**
/// - Hanya tab AKTIF yang menampilkan label (ikon filled biru brand +
///   teks). Tab non-aktif = ikon outline abu, tanpa teks.
/// - `collapsed=true` (saat user scroll konten ke bawah): label aktif
///   menyusut hilang + seluruh pill menyempit dari sisi ke tengah
///   (Gaya C). Scroll balik ke atas → melebar penuh lagi.
/// - Light variant = frosted glass (BackdropFilter blur 22 + tint putih
///   0.64 + border putih 0.70). Butuh `Scaffold(extendBody: true)` di
///   shell supaya konten tembus di belakang nav.
///
/// `variant` tetap dipertahankan agar call-site lama tidak perlu berubah.
/// - light: frosted glass putih (halaman umum)
/// - dark: frosted glass hitam untuk Feed over video (Reels style)
enum BottomNavVariant { light, dark }

const _navInactive = Color(0xFF6B7280);
// Foreground avatar fallback (inisial / ikon person tab Akun saat user tanpa
// foto). Background fallback SELALU terang (biru/abu muda), jadi warnanya
// fixed gelap-readable — TIDAK ikut inactiveColor nav, yang di varian dark
// (Feed) kini PUTIH → kalau ikut, inisial putih di atas bg terang tak terbaca.
// Border super tipis (25%→10%) — Telegram/iOS glass hampir tak berbingkai;
// border tebal bikin pill terbaca sebagai "kartu putih mengambang", bukan
// lembaran kaca bening. Cukup highlight tepi samar.
const _navLightBorder = Color(0x1AFFFFFF); // white 10% alpha (highlight tepi)
// Glass tokens Feed (varian "dark" = over video). Permintaan user (revisi):
// nav Feed harus GELAP/HITAM tembus ala Reels/TikTok — pill hitam
// semi-transparan + ikon PUTIH, video tetap tembus samar di baliknya.
// (Sebelumnya sempat dibuat kaca PUTIH + ikon gelap; dibalik lagi karena
// di atas video kaca putih terbaca kurang menyatu — user minta kembali
// gelap, cuma dibuat glass/tembus.)
// Tint hitam ~44% (0x70) — cukup pekat supaya pill jelas gelap & ikon putih
// kontras di semua frame video, tapi masih tembus (bukan solid).
const _navDarkGlass = Color(0x70111418); // near-black ~44% alpha
const _navDarkTopBorder =
    Color(0x24FFFFFF); // white ~14% (highlight tepi tipis)
const _navDarkActive = Color(0xFFFFFFFF); // putih penuh — tab aktif
const _navDarkInactive = Color(0xB8FFFFFF); // putih ~72% — tab non-aktif

// Shadow glyph tidak diperlukan: ikon putih duduk DI ATAS pill hitam
// (bukan langsung di atas video), jadi pill sendiri jadi backdrop kontras.
// Halo shadow malah bikin ikon "berbayang" (feedback user lama) → tetap null.
const List<Shadow>? _navDarkGlyphShadow = null;

// INSIGHT KUNCI (setelah bandingkan langsung dengan nav IG terbaru): kesan
// "abu"/keruh BUKAN cuma soal tint — blur sigma tinggi (34) meratakan
// warna di belakang jadi abu (color averaging), jadi walau tint sudah
// diturunkan ke 30%, hasil tetap terlihat "susu keruh", bukan "kaca
// bening". Nav IG asli pakai blur RENDAH supaya variasi warna asli (biru
// langit, oranye sunset dll) tetap tembus jelas, cuma sedikit buram tepi
// ikonnya. Blur ditahan di kisaran rendah (22) — cukup untuk frost tapi
// tidak meratakan warna jadi abu; dipasangkan dengan saturasi boost.
// FORMULA GLASS BENING (bukan frosted abu, ala Telegram): tint putih
// diturunkan drastis ke ~5% (0x0D) — nyaris tanpa lapisan susu — supaya
// konten di belakang tembus JERNIH, bukan tertutup frost. Keabu-abuan
// juga ditekan lewat blur rendah (14, lihat _glassFilter) + saturasi
// tinggi (1.5). Konsekuensi fisika: di atas area putih polos (halaman
// Produk/Transaksi) kaca tetap terlihat agak pucat karena memang tak ada
// warna di belakang untuk ditembuskan — ini sifat asli kaca bening, bukan
// bug. Di atas konten berwarna → tembus jernih berwarna.
const _navLightGlass = Color(0x0DFFFFFF); // white ~5% alpha

/// Color matrix untuk menaikkan saturasi backdrop di belakang kaca.
///
/// INI RAHASIA "bening berwarna" ala IG iOS. Blur Gaussian secara
/// matematis merata-ratakan pixel tetangga → kalau background warna-warni
/// (produk pink, badge merah), hasil rata-ratanya condong ABU. iOS
/// menambalnya dengan boost saturasi (vibrancy) supaya warna asli pop
/// kembali; Flutter BackdropFilter tidak, makanya default-nya keruh.
///
/// Kita kembalikan sendiri lewat ColorFilter.matrix di-compose dengan
/// blur. `s` = faktor saturasi (1.0 = netral, 1.4 = +40%). Rumus standar
/// luminance-preserving saturation matrix (koef ITU-R BT.601).
List<double> _saturationMatrix(double s) {
  const lumR = 0.213, lumG = 0.715, lumB = 0.072;
  final sr = (1 - s) * lumR, sg = (1 - s) * lumG, sb = (1 - s) * lumB;
  return <double>[
    sr + s,
    sg,
    sb,
    0,
    0,
    sr,
    sg + s,
    sb,
    0,
    0,
    sr,
    sg,
    sb + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// Backdrop filter kaca: blur + boost saturasi. Blur di-decouple per varian:
/// - light (halaman umum): blur RENDAH 8 (turun dari 14 — diukur via pixel
///   sampling di emulator, 14 masih meratakan warna jadi ~RGB 237 flat,
///   nyaris tak beda dari abu solid) supaya kaca BENING ala Telegram —
///   detail warna konten di belakang tidak sempat merata jadi abu.
///   Saturasi +50% untuk melawan sisa keabu-abuan.
/// - dark (Feed over video): blur diturunkan 22→14 supaya video lebih
///   TEMBUS (kaca bening, bukan frost tebal) — permintaan "transparan
///   seperti kaca". Saturasi dinaikkan 1.15→1.35 supaya warna video pop
///   melewati kaca, melawan sisa keabu-abuan dari blur.
ImageFilter _glassFilter({required bool dark}) {
  final blur = ImageFilter.blur(
    sigmaX: dark ? 14 : 8,
    sigmaY: dark ? 14 : 8,
  );
  return ImageFilter.compose(
    outer: blur,
    inner: ColorFilter.matrix(_saturationMatrix(dark ? 1.35 : 1.5)),
  );
}

/// Jarak dari tepi bawah layar yang perlu di-clear supaya konten TIDAK
/// tertutup floating nav — TIDAK termasuk safe-area device (caller tambah
/// sendiri via `MediaQuery.paddingOf(context).bottom`). Nilai = margin
/// bawah pill (10) + tinggi pill (54) + gap napas (12).
///
/// Dipakai layar full-bleed dengan overlay custom (mis. Feed video/foto
/// post — caption, action rail) yang tidak lewat `bottomNavigationBar`
/// slot Scaffold biasa, jadi perlu hitung clearance manual saat
/// `extendBody: true`.
const kFloatingNavClearance = 76.0;

class _NavItemData {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isAvatar;

  const _NavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.isAvatar = false,
  });
}

const List<_NavItemData> _navItems = [
  _NavItemData(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Beranda',
  ),
  _NavItemData(
    icon: Icons.shopping_bag_outlined,
    selectedIcon: Icons.shopping_bag_rounded,
    label: 'Produk',
  ),
  _NavItemData(
    icon: Icons.play_circle_outline_rounded,
    selectedIcon: Icons.play_circle_fill_rounded,
    label: 'Feed',
  ),
  _NavItemData(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    label: 'Transaksi',
  ),
  _NavItemData(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'Akun',
    isAvatar: true,
  ),
];

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final BottomNavVariant variant;
  final ValueChanged<int>? onDestinationSelected;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    this.variant = BottomNavVariant.light,
    this.onDestinationSelected,
  });

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final onSelected = onDestinationSelected;
    if (onSelected != null) {
      onSelected(index);
      return;
    }

    switch (index) {
      case 0:
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        break;
      case 1:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/products',
          (route) => false,
        );
        break;
      case 2:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/feed',
          (route) => false,
        );
        break;
      case 3:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/transactions',
          (route) => false,
        );
        break;
      case 4:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/member',
          (route) => false,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = variant == BottomNavVariant.dark;
    final activeColor = dark ? _navDarkActive : NataloColors.primary;
    final inactiveColor = dark ? _navDarkInactive : _navInactive;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final borderRadius = BorderRadius.circular(24);
    final borderColor = dark ? _navDarkTopBorder : _navLightBorder;
    final glassColor = dark ? _navDarkGlass : _navLightGlass;

    // Collapse dibaca dari notifier global (di-drive listener scroll di root
    // app). Berlaku sama untuk varian light & dark — Feed juga menyempit
    // saat scroll supaya konsisten dengan halaman lain.
    return ValueListenableBuilder<bool>(
      valueListenable: bottomNavCollapsed,
      builder: (context, collapsed, _) {
        final row = SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _navItems.length; i++)
                _BottomNavItem(
                  data: _navItems[i],
                  selected: currentIndex == i,
                  collapsed: collapsed,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  glyphShadows: dark ? _navDarkGlyphShadow : null,
                  onTap: () => _onTap(context, i),
                ),
            ],
          ),
        );

        // Frosted glass 3-lapis: blur (BackdropFilter) + tint (glassColor) +
        // border tipis. Sama untuk light & dark, beda cuma warna tint/border.
        final pill = ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: _glassFilter(dark: dark),
            child: Container(
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: borderRadius,
                border: Border.all(color: borderColor, width: 0.5),
                boxShadow: dark
                    ? null
                    : [
                        // Bayangan sangat halus + tipis — cukup memisahkan
                        // kaca dari konten putih tanpa membuatnya terlihat
                        // seperti kartu solid mengambang (Telegram/iOS: nyaris
                        // tanpa shadow). Diturunkan dari 0.12/blur20/offset8.
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: row,
            ),
          ),
        );

        // Gaya C — margin samping membesar saat collapsed → pill menyempit
        // ke tengah. Margin bawah selalu clear home indicator + gap.
        return AnimatedPadding(
          // Durasi dinaikkan 320→420 + curve lebih lembut supaya menyempit/
          // melebar terasa tenang, tidak "menyentak". Threshold di
          // updateBottomNavScroll mencegah toggle terlalu sering.
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          padding: EdgeInsets.fromLTRB(
            collapsed ? 52 : 8,
            6,
            collapsed ? 52 : 8,
            bottomInset + 10,
          ),
          child: pill,
        );
      },
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final _NavItemData data;
  final bool selected;
  final bool collapsed;
  final Color activeColor;
  final Color inactiveColor;
  final List<Shadow>? glyphShadows;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.data,
    required this.selected,
    required this.collapsed,
    required this.activeColor,
    required this.inactiveColor,
    required this.glyphShadows,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    // Label hanya muncul saat tab AKTIF dan nav TIDAK collapsed (Arah 1).
    final showLabel = selected && !collapsed;

    final iconWidget = data.isAvatar
        ? _NavBounce(
            selected: selected,
            child: AnimatedBuilder(
              animation: memberStore,
              builder: (context, _) => _AvatarIcon(
                selected: selected,
                activeColor: activeColor,
              ),
            ),
          )
        : _NavBounce(
            selected: selected,
            child: Icon(
              selected ? data.selectedIcon : data.icon,
              color: color,
              size: 25,
              shadows: glyphShadows,
            ),
          );

    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: activeColor.withValues(alpha: 0.08),
          highlightColor: activeColor.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                // AnimatedSize: label melebar/menyusut halus saat tab jadi
                // aktif atau saat collapse.
                AnimatedSize(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeInOutCubic,
                  child: showLabel
                      ? Padding(
                          padding: const EdgeInsets.only(left: 7),
                          child: Text(
                            data.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: TextStyle(
                              color: activeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              // Sama seperti ikon di sampingnya — label butuh
                              // proteksi yang sama setelah tint dark diturunkan
                              // (lihat _navDarkGlyphShadow), supaya tidak jadi
                              // satu-satunya elemen yang kurang kebaca di frame
                              // video terang.
                              shadows: glyphShadows,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bounce halus untuk ikon nav: memantul sekali (~1.14×) saat item jadi
/// terpilih — dipicu saat mendarat di tab (mount selected) atau saat
/// `selected` berubah false→true.
class _NavBounce extends StatefulWidget {
  final bool selected;
  final Widget child;

  const _NavBounce({required this.selected, required this.child});

  @override
  State<_NavBounce> createState() => _NavBounceState();
}

class _NavBounceState extends State<_NavBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.14, end: 0.98)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 32,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.98, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 26,
      ),
    ]).animate(_controller);
    if (widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward(from: 0);
      });
    }
  }

  @override
  void didUpdateWidget(_NavBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Tab Akun varian dengan avatar foto profil user (Instagram-style).
/// Ring warna activeColor saat aktif; fallback inisial/person icon.
class _AvatarIcon extends StatelessWidget {
  final bool selected;
  final Color activeColor;

  const _AvatarIcon({
    required this.selected,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    final photoUrl = profile?.profilePhotoUrl;
    final initial = profile?.initial ?? '';
    // Slot 26px match icon size non-avatar (25) + ring.
    const slotSize = 26.0;
    const ringWidth = 2.0;
    final avatarSize = selected ? slotSize - (ringWidth * 2) : slotSize;
    return SizedBox(
      width: slotSize,
      height: slotSize,
      child: Center(
        child: Container(
          width: selected ? slotSize : avatarSize,
          height: selected ? slotSize : avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: activeColor, width: ringWidth)
                : null,
          ),
          padding: selected ? const EdgeInsets.all(ringWidth - 0.5) : null,
          child: ProfileAvatar(
            initial: initial.isEmpty ? 'N' : initial,
            imageUrl: photoUrl,
            size: avatarSize,
            fontSize: 11,
            isOfficial: profile?.isAdmin ?? false,
            plain: true,
          ),
        ),
      ),
    );
  }
}
