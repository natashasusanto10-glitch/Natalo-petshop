import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/natalo_colors.dart';

/// Bar composer chat — ikon kamera + input pill + tombol kirim bundar yang
/// muncul begitu ada teks. Murni presentational: controller/lifecycle teks
/// & aksi kirim/attach dikelola pemanggil (`ChatRoomScreen`) supaya widget
/// ini tetap ringan & gampang dipakai ulang.
class ChatComposer extends StatefulWidget {
  final TextEditingController controller;

  /// Tap ikon kamera. Kirim foto sesungguhnya (`image_picker` + kompresi +
  /// upload) baru Task 5 — pemanggil boleh mengisi ini dengan stub TODO.
  final VoidCallback onAttachPhoto;

  /// Tap kirim / submit keyboard. Dipanggil dengan teks ter-trim (caller
  /// sudah pasti teksnya tidak kosong — tombol kirim hanya tampil saat ada
  /// teks, dan `onSubmitted` di-guard sama di sini).
  final ValueChanged<String> onSend;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.onAttachPhoto,
    required this.onSend,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea (bottom: true, default) sudah menangani inset gesture-bar —
    // padding di sini murni jarak visual dari border atas/tepi, bukan
    // kompensasi inset device.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: NataloColors.white,
        border: Border(top: BorderSide(color: NataloColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: widget.onAttachPhoto,
                tooltip: 'Kirim foto',
                icon: const Icon(
                  Icons.camera_alt_outlined,
                  size: 24,
                  color: NataloColors.textSecondary,
                ),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: NataloColors.surface,
                    borderRadius: AppRadius.pill,
                  ),
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontSize: 14,
                      color: NataloColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Tulis pesan…',
                      hintStyle: TextStyle(
                        color: NataloColors.textTertiary,
                        fontSize: 14,
                      ),
                      // `border: none` saja TIDAK cukup — theme global punya
                      // `enabledBorder`/`focusedBorder` (OutlineInputBorder
                      // biru saat fokus) yang fallback-nya terpisah dari
                      // `border`, jadi harus di-none-kan satu-satu.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _hasText
                    ? _SendButton(
                        key: const ValueKey('chat-send'), onTap: _submit)
                    : const SizedBox(
                        key: ValueKey('chat-send-empty'),
                        width: 40,
                        height: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SendButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NataloColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.send_rounded, color: NataloColors.white, size: 18),
        ),
      ),
    );
  }
}
