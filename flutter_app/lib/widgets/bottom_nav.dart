import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../state/member_store.dart';

/// Bottom nav bar Natalo: compact, integrated, 5 menu utama.
///
/// Index urutan:
///  0 = Beranda    /
///  1 = Produk     /products
///  2 = Feed       /feed
///  3 = Transaksi  /transactions   ⭐ NEW
///  4 = Akun       /member
///
/// `variant` tetap dipertahankan agar call-site lama tidak perlu berubah.
/// - light: putih polos seperti marketplace besar (rendah, separator tipis)
/// - dark: GLASS hitam (semi-transparent + BackdropFilter blur) untuk
///   Feed page over video — visual Reels/TikTok style.
enum BottomNavVariant { light, dark }

const _navBackground = Color(0xFFFFFFFF);
const _navTopBorder = Color(0xFFE5E7EB);
const _navActiveBlue = Color(0xFF2563EB);
const _navInactive = Color(0xFF6B7280);
// Dark glass tokens — semi-transparent black supaya video di belakang
// masih kelihatan, blur untuk feel "frosted glass dark mode".
const _navDarkGlass = Color(0xCC0A0A0A); // black 80% alpha
const _navDarkTopBorder = Color(0x33FFFFFF); // white 20% alpha
const _navDarkActive = Color(0xFFFFFFFF);
const _navDarkInactive = Color(0xFF9CA3AF);

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
    final background = dark ? _navDarkGlass : _navBackground;
    final borderColor = dark ? _navDarkTopBorder : _navTopBorder;
    final activeColor = dark ? _navDarkActive : _navActiveBlue;
    final inactiveColor = dark ? _navDarkInactive : _navInactive;

    final content = Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        // Ultra-compact nav — 46px content. Tokopedia/Lazada exact match.
        // Total iPhone notch: 46 + 34 safe = 80px. Android gesture:
        // 46 + ~20 = 66px. Lebih kecil dari 50px sebelumnya, masih
        // accommodate icon 24 + label 11.5 dengan padding tight.
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Beranda',
                selected: currentIndex == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 0),
              ),
              _BottomNavItem(
                icon: Icons.shopping_bag_outlined,
                selectedIcon: Icons.shopping_bag_rounded,
                label: 'Produk',
                selected: currentIndex == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 1),
              ),
              _BottomNavItem(
                icon: Icons.play_circle_outline_rounded,
                selectedIcon: Icons.play_circle_fill_rounded,
                label: 'Feed',
                selected: currentIndex == 2,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 2),
              ),
              _BottomNavItem(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long_rounded,
                label: 'Transaksi',
                selected: currentIndex == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 3),
              ),
              // Tab Akun pakai avatar foto profil (Instagram-style).
              // Listen ke memberStore supaya saat user upload foto baru
              // / logout / login, icon auto-update. Ukuran icon SAMA
              // dengan tab lain — slot kotak 24px, supaya bottom nav
              // height tetap 46px (NO change ke nav structure).
              _BottomNavAvatarItem(
                label: 'Akun',
                selected: currentIndex == 4,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 4),
              ),
            ],
          ),
        ),
      ),
    );

    // Dark variant pakai true glass effect — BackdropFilter blur video di
    // belakang. Light variant solid putih, no blur (no GPU cost).
    if (dark) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: content,
        ),
      );
    }
    return content;
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: activeColor.withValues(alpha: 0.08),
            highlightColor: activeColor.withValues(alpha: 0.06),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.02 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        selected ? selectedIcon : icon,
                        color: color,
                        size: selected ? 24 : 23,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        height: 1,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tab Akun varian dengan avatar foto profil user (Instagram-style).
///
/// Render persis di slot ukuran yang sama dengan _BottomNavItem reguler
/// supaya bottom nav height TIDAK berubah (tetap 46px). Cuma swap konten
/// icon dari IconData ke CircleAvatar 22px.
///
/// State changes:
///  - Listen `memberStore` → kalau profile.photoUrl berubah (user upload
///    foto baru), avatar auto-refresh.
///  - Active state: 2px ring warna activeColor di sekeliling avatar.
///  - Inactive state: no ring, plain avatar.
///  - Fallback kalau profile null / photo null: pakai inisial nama atau
///    default person icon (sama style dengan _BottomNavItem reguler).
class _BottomNavAvatarItem extends StatelessWidget {
  final String label;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _BottomNavAvatarItem({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: activeColor.withValues(alpha: 0.08),
            highlightColor: activeColor.withValues(alpha: 0.06),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.02 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: AnimatedBuilder(
                        animation: memberStore,
                        builder: (context, _) {
                          return _AvatarIcon(
                            selected: selected,
                            activeColor: activeColor,
                            inactiveColor: color,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        height: 1,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarIcon extends StatelessWidget {
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;

  const _AvatarIcon({
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    final photoUrl = profile?.profilePhotoUrl;
    final initial = profile?.initial ?? '';
    // Slot size 24px (match _BottomNavItem icon size 23-24). Ring +2px
    // saat active masuk ke padding luar — total tetap 24×24 dengan ring,
    // jadi visual size sama dengan icon tab lain.
    const slotSize = 24.0;
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
          child: ClipOval(
            child: photoUrl != null && photoUrl.trim().isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _AvatarFallback(
                      initial: initial,
                      color: inactiveColor,
                    ),
                    errorWidget: (_, __, ___) => _AvatarFallback(
                      initial: initial,
                      color: inactiveColor,
                    ),
                  )
                : _AvatarFallback(initial: initial, color: inactiveColor),
          ),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String initial;
  final Color color;

  const _AvatarFallback({required this.initial, required this.color});

  @override
  Widget build(BuildContext context) {
    if (initial.isEmpty) {
      // No inisial (guest) → pakai default person icon.
      return Container(
        color: const Color(0xFFE5E7EB),
        child: Icon(
          Icons.person_rounded,
          color: color,
          size: 16,
        ),
      );
    }
    return Container(
      color: const Color(0xFFE0E7FF),
      alignment: Alignment.center,
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
