import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../services/feed_service.dart';
import '../utils/haptics.dart';
import '../widgets/loading_button.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// **Edit Caption / Tag** screen — native editor untuk own feed post.
///
/// Replace web fallback yang sebelumnya dipakai di action sheet "Aksi
/// postingan" (member_post_detail_screen). Match Capacitor UX:
/// - Form 3 field: title, description, tags (chip-style add)
/// - Save → call feedService.updatePostCaption() → pop dengan return value
/// - Cancel button kalau ada unsaved changes → konfirmasi dialog
class MemberPostEditScreen extends StatefulWidget {
  final MyFeedPost post;

  const MemberPostEditScreen({super.key, required this.post});

  @override
  State<MemberPostEditScreen> createState() => _MemberPostEditScreenState();
}

class _MemberPostEditScreenState extends State<MemberPostEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _tagInputController;
  late List<String> _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.post.title ?? '');
    _descController =
        TextEditingController(text: widget.post.description ?? '');
    _tagInputController = TextEditingController();
    // Tags ada di model — init dari post existing supaya user bisa edit
    // (tambah/hapus) tag yang sudah ada.
    _tags = List<String>.from(widget.post.tags);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    if (_titleController.text.trim() != (widget.post.title ?? '').trim()) {
      return true;
    }
    if (_descController.text.trim() !=
        (widget.post.description ?? '').trim()) {
      return true;
    }
    if (_tags.length != widget.post.tags.length) return true;
    for (var i = 0; i < _tags.length; i++) {
      if (_tags[i] != widget.post.tags[i]) return true;
    }
    return false;
  }

  void _addTag() {
    final raw = _tagInputController.text.trim();
    if (raw.isEmpty) return;
    // Strip "#" prefix kalau user input
    final cleaned = raw.startsWith('#') ? raw.substring(1) : raw;
    if (cleaned.isEmpty) return;
    if (_tags.contains(cleaned)) {
      _tagInputController.clear();
      return;
    }
    if (_tags.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maksimal 8 tag.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _tags = [..._tags, cleaned];
      _tagInputController.clear();
    });
    AppHaptics.tap();
  }

  void _removeTag(String tag) {
    setState(() => _tags = _tags.where((t) => t != tag).toList());
    AppHaptics.tap();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await feedService.updatePostCaption(
        id: widget.post.id,
        title: _titleController.text,
        description: _descController.text,
        tags: _tags,
      );
      if (!mounted) return;
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caption berhasil di-update.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal update: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Buang perubahan?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Caption dan tag yang sudah kamu edit akan hilang.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Capture Navigator BEFORE await supaya tidak deref context post-async.
        final navigator = Navigator.of(context);
        final shouldClose = await _confirmDiscard();
        if (!mounted) return;
        if (shouldClose) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: const Color(0xFFF8FAFC),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF17202A),
            ),
            tooltip: 'Kembali',
            onPressed: () async {
              final navigator = Navigator.of(context);
              final shouldClose = await _confirmDiscard();
              if (!mounted) return;
              if (shouldClose) navigator.pop();
            },
          ),
          title: const Text(
            'Edit Caption',
            style: TextStyle(
              color: Color(0xFF17202A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ── Title field ──
            const _FieldLabel('Judul'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: 'Contoh: Anjing saya suka banget!',
              ),
            ),
            const SizedBox(height: 12),
            // ── Description field ──
            const _FieldLabel('Deskripsi'),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 5,
              minLines: 3,
              maxLength: 500,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText:
                    'Ceritakan tentang video kamu — produk yang dipakai, '
                    'alasan rekomen, atau momen lucu peliharaanmu.',
              ),
            ),
            const SizedBox(height: 12),
            // ── Tags ──
            const _FieldLabel('Tag (maks. 8)'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag input row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagInputController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addTag(),
                          decoration: const InputDecoration(
                            hintText: 'mis. anjing, kucing, vitamin',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addTag,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: const Text('Tambah'),
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in _tags)
                          _TagChip(label: tag, onRemove: () => _removeTag(tag)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ── Save button ──
            LoadingButton(
              onPressed: _hasChanges ? _save : null,
              loading: _saving,
              color: _brandBlue,
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF111111),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _TagChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$label',
            style: const TextStyle(
              color: _brandBlue,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                color: _brandBlue,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
