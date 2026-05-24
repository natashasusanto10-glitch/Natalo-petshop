import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/haptics.dart';

const _captionBlue = Color(0xFF1E5BFF);
const _captionInk = Color(0xFF101828);
const _captionMuted = Color(0xFF98A2B3);

/// Caption edit modal — fade-in overlay di atas Post Baru.
///
/// Layout match Final Lock Spec:
///  - Bottom: dim layer (Colors.black opacity 0.55) — Post Baru tetap visible
///    underneath dengan dim effect, supaya user feel "balik" gampang.
///  - Top: white sheet (~50-55% layar) dengan header (back + "Caption" + "OK")
///    + TextField caption multiline plain (no border, no counter, no emoji).
///  - Keyboard naik dari bawah, push area input lebih ke tengah.
///
/// Return value:
///  - Tap OK         → pop dengan caption text (commit changes).
///  - Tap back arrow → pop dengan caption text (BACK = SAVE, per IG pattern).
///  - System back    → sama dengan back arrow (save).
///
/// Cross-platform:
///  - iOS: keyboardAppearance = light (match white sheet).
///  - Android: theme default (Android handle dari system).
///  - SafeArea + MediaQuery.viewInsets.bottom aware untuk keyboard avoid.
class FeedCaptionEditScreen extends StatefulWidget {
  final String initialCaption;

  const FeedCaptionEditScreen({
    super.key,
    this.initialCaption = '',
  });

  @override
  State<FeedCaptionEditScreen> createState() => _FeedCaptionEditScreenState();
}

class _FeedCaptionEditScreenState extends State<FeedCaptionEditScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCaption);
    // Auto-focus caption field dengan slight delay supaya keyboard tidak
    // race dengan fade-in transition (180ms). Smoother UX.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitAndPop() {
    AppHaptics.tap();
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept system back — commit caption changes (BACK = SAVE per UX
      // decision). Manual pop di handler.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_controller.text);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // resizeToAvoidBottomInset: false supaya keyboard tidak push sheet
        // ke atas — sheet tetap di top, keyboard naik di atas dim layer.
        // Dim layer + Post Baru behind tetap visible di antara sheet & kbd.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── Dim underlay ── tap area bawah sheet → commit & pop.
            // Bottom area show Post Baru dengan dim 55% opacity (cukup
            // gelap supaya focus naik ke caption sheet di atas).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _commitAndPop,
                child: Container(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
            // ── White caption sheet ── di top, mainAxisSize.min supaya
            // hanya setinggi konten (header + textfield). Tidak ada bottom
            // padding keyboard — biar dim layer di bawah keliatan. Keyboard
            // muncul OS-side di atas dim, tidak meng-cover sheet.
            Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Colors.white,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CaptionHeader(
                        onBack: _commitAndPop,
                        onOk: _commitAndPop,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.6,
                        color: Color(0xFFE5EAF2),
                      ),
                      // TextField plain — no border, no counter, no emoji,
                      // no box. minLines 4 supaya sheet ada visual weight
                      // tapi tetap compact (~110px) — sisanya dim layer
                      // di bawah keliatan Post Baru behind.
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 14, 20, 18),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          minLines: 4,
                          maxLines: 8,
                          // iOS light keyboard match white sheet background.
                          keyboardAppearance: Brightness.light,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          cursorColor: _captionBlue,
                          style: const TextStyle(
                            color: _captionInk,
                            fontSize: 16,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                          // Plain TextField — NO border, NO background.
                          //
                          // Catatan: TIDAK boleh pakai
                          // `InputDecoration.collapsed` saja karena global
                          // `inputDecorationTheme` di app_theme.dart punya
                          // `enabledBorder`, `focusedBorder`, `filled:true`,
                          // dll yang merge di atas decoration → outline
                          // biru tetap render saat focus.
                          //
                          // Solusi: explicit override SEMUA border state
                          // ke `InputBorder.none` + `filled: false` +
                          // `fillColor: transparent` supaya theme tidak
                          // menang. Pattern ini bypass theme global
                          // untuk field spesifik ini saja.
                          decoration: const InputDecoration(
                            hintText: 'Tulis caption...',
                            hintStyle: TextStyle(
                              color: _captionMuted,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            fillColor: Colors.transparent,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaptionHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onOk;

  const _CaptionHeader({
    required this.onBack,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          // Back arrow — kiri.
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: _captionInk,
                size: 24,
              ),
              tooltip: 'Kembali',
            ),
          ),
          // Title center.
          const Center(
            child: Text(
              'Caption',
              style: TextStyle(
                color: _captionInk,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // OK button blue — kanan.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOk,
              style: TextButton.styleFrom(
                foregroundColor: _captionBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper untuk push Caption editor sebagai fade-modal (bukan slide push).
/// Match IG/TikTok feel: instant fade-in over current screen.
///
/// Return:
///  - String → caption baru (boleh kosong).
///  - null   → tidak pernah terjadi (back/OK selalu return current text).
Future<String?> showCaptionEditModal(
  BuildContext context, {
  required String initialCaption,
}) {
  // Hide soft keyboard kalau ada (defensive — biasanya tidak ada karena
  // caller dari trigger button, but safe).
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, __, ___) =>
          FeedCaptionEditScreen(initialCaption: initialCaption),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: child,
      ),
    ),
  );
}
