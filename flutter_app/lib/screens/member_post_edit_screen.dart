import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

/// Edit Postingan — edit caption + manage tagged products.
/// Video/thumbnail tidak bisa di-edit (replace upload ulang).
class MemberPostEditScreen extends StatefulWidget {
  final MyFeedPost post;

  const MemberPostEditScreen({super.key, required this.post});

  @override
  State<MemberPostEditScreen> createState() => _MemberPostEditScreenState();
}

class _MemberPostEditScreenState extends State<MemberPostEditScreen> {
  late final TextEditingController _captionController;
  bool _saving = false;

  static const _maxCaptionLength = 280;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption ?? '');
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    AppHaptics.tap();
    setState(() => _saving = true);
    // TODO: integrate dengan feedService.updateMyPost(postId, caption, productIds).
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(
      context,
      'Update caption belum tersambung ke backend.\nSementara via PWA web.',
      kind: ToastKind.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text('Edit Postingan'),
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Video preview thumbnail
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AspectRatio(
              aspectRatio: widget.post.aspectWidth / widget.post.aspectHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.post.thumbnailUrl != null &&
                      widget.post.thumbnailUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        widget.post.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(),
                      ),
                    ),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Video tidak bisa diganti. Untuk video baru, hapus postingan lalu upload ulang.',
              style: TextStyle(
                color: NataloColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Caption editor
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Caption',
              style: TextStyle(
                color: NataloColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextField(
            controller: _captionController,
            maxLines: 5,
            minLines: 3,
            maxLength: _maxCaptionLength,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: 'Tulis caption postingan…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Tagged products section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE8F8)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE7F3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_offer_outlined,
                    color: Color(0xFFBE185D),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Produk Ditag',
                        style: TextStyle(
                          color: NataloColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.post.productIds.isEmpty
                            ? 'Belum ada produk'
                            : '${widget.post.productIds.length} produk ditag',
                        style: const TextStyle(
                          color: NataloColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    AppHaptics.tap();
                    AppToast.show(
                      context,
                      'Edit tag produk belum tersedia di Flutter.',
                    );
                  },
                  child: const Text(
                    'Atur',
                    style: TextStyle(
                      color: NataloColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Simpan Perubahan'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text(
              'Batal',
              style: TextStyle(
                color: NataloColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
