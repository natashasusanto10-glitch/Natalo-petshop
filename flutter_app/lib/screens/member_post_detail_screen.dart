import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/my_feed_post.dart';
import '../services/feed_service.dart';
import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// "Detail Postingan" screen — match PWA `app/akun/postingan-saya/[id]/page.tsx`.
/// Layout: video thumbnail besar dengan play overlay + info card (judul + tanggal
/// + status pill + description), info video (durasi + status review), CTA actions
/// (Lihat Detail di web / Hapus).
class MemberPostDetailScreen extends StatefulWidget {
  final MyFeedPost post;

  const MemberPostDetailScreen({super.key, required this.post});

  @override
  State<MemberPostDetailScreen> createState() => _MemberPostDetailScreenState();
}

class _MemberPostDetailScreenState extends State<MemberPostDetailScreen> {
  bool _deleting = false;

  MyFeedPost get post => widget.post;

  Future<void> _confirmDelete() async {
    AppHaptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  post.status == MyFeedPostStatus.active
                      ? 'Hapus video ini?'
                      : 'Hapus postingan ini?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  post.status == MyFeedPostStatus.active
                      ? 'Video akan dihapus dari Feed dan tidak bisa dilihat user lain. Tindakan ini tidak bisa dibatalkan.'
                      : 'Postingan akan dihapus dari daftar Postingan Saya. Tindakan ini tidak bisa dibatalkan.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Batal',
                          style: TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Hapus Video',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _delete();
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await feedService.deletePost(post.id);
      if (!mounted) return;
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            post.status == MyFeedPostStatus.active
                ? 'Video berhasil dihapus.'
                : 'Postingan berhasil dihapus.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal hapus: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _openInBrowser() async {
    AppHaptics.tap();
    final url = Uri.parse('https://natalopetshop.com/akun/postingan-saya/${post.id}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openEditCaption() async {
    AppHaptics.tap();
    // Native edit screen — full form (title + description + tags) dengan
    // discard-confirmation kalau ada unsaved changes. Match Capacitor flow.
    final updated = await Navigator.pushNamed(
      context,
      '/member/postingan-edit',
      arguments: post,
    );
    // Kalau update sukses, refresh order untuk dapat data terbaru.
    if (updated == true && mounted) {
      Navigator.pop(context, true); // signal parent untuk reload
    }
  }

  /// Show bottom sheet "Aksi postingan" — match Capacitor pattern.
  /// Options: Edit caption/tag | Hapus dari Feed (destructive) | Batal.
  Future<void> _showActionSheet() async {
    AppHaptics.tap();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    height: 4,
                    width: 40,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header: "Aksi postingan" + close X
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Aksi postingan',
                        style: TextStyle(
                          color: Color(0xFF111111),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          color: Color(0xFF6B7280),
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(color: Color(0xFFE5E7EB), height: 1),
                // Edit caption / tag
                _ActionSheetRow(
                  icon: Icons.edit_outlined,
                  iconColor: const Color(0xFF111111),
                  label: 'Edit caption / tag',
                  textColor: const Color(0xFF111111),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 22,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openEditCaption();
                  },
                ),
                const Divider(color: Color(0xFFE5E7EB), height: 1),
                // Hapus dari Feed (destructive — red text + red icon, NOT filled)
                _ActionSheetRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFFEF4444),
                  label: post.status == MyFeedPostStatus.active
                      ? 'Hapus dari Feed'
                      : 'Hapus Postingan',
                  textColor: const Color(0xFFEF4444),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete();
                  },
                ),
                const Divider(color: Color(0xFFE5E7EB), height: 1),
                // Batal
                _ActionSheetRow(
                  icon: Icons.close_rounded,
                  iconColor: const Color(0xFF6B7280),
                  label: 'Batal',
                  textColor: const Color(0xFF6B7280),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0xFFF8FAFC),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF17202A)),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Detail Postingan',
          style: TextStyle(
            color: Color(0xFF17202A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        actions: [
          // 3-dots menu trigger — match Capacitor "Aksi postingan" sheet.
          IconButton(
            onPressed: _showActionSheet,
            tooltip: 'Aksi postingan',
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Color(0xFF17202A),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── Video thumbnail dengan play overlay + duration badge ──
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (post.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: post.thumbnailUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 180),
                      placeholder: (_, __) =>
                          const ColoredBox(color: Color(0xFFE5E7EB)),
                      errorWidget: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFFE5E7EB)),
                    )
                  else
                    const ColoredBox(color: Color(0xFFE5E7EB)),
                  Center(
                    child: Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.70),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        post.durationLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ── Title + date + status card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title?.trim().isNotEmpty == true
                      ? post.title!
                      : 'Tanpa judul',
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(post.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatusPanel(status: post.status, note: post.moderationNote),
                if (post.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE5E7EB), height: 1),
                  const SizedBox(height: 10),
                  const Text(
                    'Deskripsi',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.description!,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Info Video card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informasi Video',
                  style: TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.access_time_rounded,
                  label: 'Durasi',
                  value: post.durationLabel,
                ),
                const Divider(color: Color(0xFFE5E7EB), height: 18),
                _InfoRow(
                  icon: Icons.play_arrow_rounded,
                  label: 'Status review',
                  value: post.status.label,
                  valueColor: _statusColor(post.status),
                ),
                if (post.status != MyFeedPostStatus.pending) ...[
                  const Divider(color: Color(0xFFE5E7EB), height: 18),
                  _InfoRow(
                    icon: Icons.bar_chart_rounded,
                    label: 'Performa',
                    value:
                        '${post.likeCount} like · ${post.commentCount} comment · ${post.shareCount} share',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── "Lihat Detail" inline button — open web version ──
          // Delete + Edit dipindah ke "Aksi postingan" bottom sheet via 3-dots
          // di AppBar (match Capacitor pattern). "Lihat Detail" tetap inline
          // karena viewing, bukan destructive action.
          OutlinedButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Lihat Detail di Web'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandBlue,
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (_deleting) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Row di dalam "Aksi postingan" bottom sheet — match Capacitor pattern.
/// Icon kiri (warna sesuai role) + label + optional trailing (chevron untuk
/// navigasi, tidak ada untuk destructive/dismiss).
class _ActionSheetRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color textColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ActionSheetRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.textColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

Color _statusColor(MyFeedPostStatus status) {
  switch (status) {
    case MyFeedPostStatus.active:
      return const Color(0xFF047857);
    case MyFeedPostStatus.rejected:
      return const Color(0xFFEF4444);
    case MyFeedPostStatus.pending:
      return const Color(0xFF92400E);
    case MyFeedPostStatus.unknown:
      return const Color(0xFF6B7280);
  }
}

class _StatusPanel extends StatelessWidget {
  final MyFeedPostStatus status;
  final String? note;
  const _StatusPanel({required this.status, this.note});

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color border;
    late final Color fg;
    switch (status) {
      case MyFeedPostStatus.active:
        bg = const Color(0xFFD1FAE5).withValues(alpha: 0.65);
        border = const Color(0xFFA7F3D0);
        fg = const Color(0xFF047857);
        break;
      case MyFeedPostStatus.rejected:
        bg = const Color(0xFFFEE2E2).withValues(alpha: 0.80);
        border = const Color(0xFFFECACA);
        fg = const Color(0xFFEF4444);
        break;
      case MyFeedPostStatus.pending:
        bg = const Color(0xFFFEF3C7).withValues(alpha: 0.80);
        border = const Color(0xFFFDE68A);
        fg = const Color(0xFF92400E);
        break;
      case MyFeedPostStatus.unknown:
        bg = const Color(0xFFEFF2F6);
        border = const Color(0xFFE5E7EB);
        fg = const Color(0xFF6B7280);
        break;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status.description,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: TextStyle(
                color: fg.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF2F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF475569), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? const Color(0xFF111111),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hh:$mm';
}
