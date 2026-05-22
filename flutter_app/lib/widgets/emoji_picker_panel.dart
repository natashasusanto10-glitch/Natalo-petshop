import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// Bottom panel emoji picker — appear di atas keyboard saat user tap
/// tombol 😀 di samping caption/comment input. Match IG/TikTok layout.
///
/// **Insertion behavior**: insert ke posisi cursor controller, supaya
/// user yang sudah ngetik "Halo " bisa tap emoji → jadi "Halo 👋". Bukan
/// append ke end. Cursor di-update ke setelah emoji yang baru di-insert.
///
/// **Visibility control** via `visible` prop. Parent kontrol show/hide.
/// Saat `visible=true`, panel height ~280 (cukup untuk 1 row preview +
/// 6 row emoji + bottom category bar). Saat hide, return SizedBox.shrink.
///
/// Pakai default `emoji_picker_flutter` config — Unicode-only (no asset),
/// cross-platform rendering. Backspace + search bar built-in.
class EmojiPickerPanel extends StatelessWidget {
  final TextEditingController controller;
  final bool visible;
  final double height;

  const EmojiPickerPanel({
    super.key,
    required this.controller,
    required this.visible,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: EmojiPicker(
        textEditingController: controller,
        config: Config(
          height: height,
          checkPlatformCompatibility: true,
          emojiViewConfig: const EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 28,
            backgroundColor: Colors.white,
            verticalSpacing: 2,
            horizontalSpacing: 0,
            recentsLimit: 28,
          ),
          categoryViewConfig: const CategoryViewConfig(
            backgroundColor: Colors.white,
            indicatorColor: Color(0xFF0B7FEA),
            iconColor: Color(0xFF9CA3AF),
            iconColorSelected: Color(0xFF0B7FEA),
            categoryIcons: CategoryIcons(),
            tabIndicatorAnimDuration: Duration(milliseconds: 220),
            initCategory: Category.SMILEYS,
          ),
          bottomActionBarConfig: const BottomActionBarConfig(
            backgroundColor: Colors.white,
            buttonColor: Colors.white,
            buttonIconColor: Color(0xFF6B7280),
            showBackspaceButton: true,
            showSearchViewButton: true,
          ),
          searchViewConfig: const SearchViewConfig(
            backgroundColor: Colors.white,
            buttonIconColor: Color(0xFF6B7280),
            hintText: 'Cari emoji…',
          ),
        ),
      ),
    );
  }
}
