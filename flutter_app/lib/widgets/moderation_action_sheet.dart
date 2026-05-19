import 'package:flutter/material.dart';

import '../services/block_service.dart';
import '../services/report_service.dart';

/// Bottom sheet untuk action moderasi: Laporkan + Blokir user.
///
/// Dipakai di 3 lokasi (Google Play UGC policy requirement):
/// 1. [feed_screen.dart] — long-press / tap "more" pada feed post
/// 2. [feed_comment_sheet.dart] — long-press pada comment
/// 3. [member_reviews_screen.dart] — tap "more" pada product review
///
/// Pattern: caller open sheet via [showModerationActions], yang return
/// optional [ModerationActionResult] kalau user trigger sesuatu yang
/// perlu refresh UI (mis. block → caller filter list dari blocked user).
class ModerationActionResult {
  /// User trigger block → caller harus refresh list supaya post/review
  /// dari user ini hilang.
  final bool didBlock;

  /// User trigger report → caller bisa show toast / dim item.
  final bool didReport;

  const ModerationActionResult({
    this.didBlock = false,
    this.didReport = false,
  });
}

/// Open bottom sheet dengan opsi report + block.
///
/// [authorId] dan [authorName] dipakai untuk block. Salah satu wajib
/// (preferensi ID kalau ada).
Future<ModerationActionResult?> showModerationActions(
  BuildContext context, {
  required ReportTargetKind targetKind,
  required String targetId,
  String? authorId,
  String? authorName,
  bool allowBlock = true,
}) {
  return showModalBottomSheet<ModerationActionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ModerationSheet(
      targetKind: targetKind,
      targetId: targetId,
      authorId: authorId,
      authorName: authorName,
      allowBlock: allowBlock,
    ),
  );
}

class _ModerationSheet extends StatelessWidget {
  final ReportTargetKind targetKind;
  final String targetId;
  final String? authorId;
  final String? authorName;
  final bool allowBlock;

  const _ModerationSheet({
    required this.targetKind,
    required this.targetId,
    this.authorId,
    this.authorName,
    required this.allowBlock,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grip bar.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // Report action.
            _ActionTile(
              icon: Icons.flag_outlined,
              iconColor: const Color(0xFFEF4444),
              label: 'Laporkan ${targetKind.displayLabel}',
              subtitle: 'Kirim ke moderator Natalo untuk ditinjau',
              onTap: () async {
                final result = await _openReportFlow(context);
                if (!context.mounted) return;
                Navigator.of(context).pop(
                  ModerationActionResult(didReport: result),
                );
              },
            ),
            if (allowBlock &&
                (authorId != null || (authorName?.isNotEmpty ?? false))) ...[
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _ActionTile(
                icon: Icons.block_outlined,
                iconColor: const Color(0xFF6B7280),
                label: authorName != null && authorName!.isNotEmpty
                    ? 'Blokir $authorName'
                    : 'Blokir pengguna ini',
                subtitle: 'Sembunyikan semua konten dari pengguna ini',
                onTap: () async {
                  final confirmed = await _confirmBlock(context);
                  if (!confirmed) return;
                  await blockService.blockUser(
                    userId: authorId,
                    userName: authorName,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop(
                    const ModerationActionResult(didBlock: true),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        authorName != null && authorName!.isNotEmpty
                            ? '$authorName diblokir. Konten dari pengguna ini disembunyikan.'
                            : 'Pengguna diblokir.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            _ActionTile(
              icon: Icons.close_rounded,
              iconColor: const Color(0xFF6B7280),
              label: 'Batal',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool> _openReportFlow(BuildContext context) async {
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReasonPickerSheet(targetKind: targetKind),
    );
    if (reason == null) return false;
    final ok = await _submitReport(context, reason);
    return ok;
  }

  Future<bool> _submitReport(
    BuildContext context,
    ReportReason reason,
  ) async {
    // Optimistic: tampilkan toast sukses immediately, kirim di background.
    // Kalau gagal, tampilkan error toast.
    final result = await reportService.submit(
      targetKind: targetKind,
      targetId: targetId,
      reason: reason,
    );
    if (!context.mounted) return result.ok;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'Laporan terkirim. Moderator akan meninjau dalam 24 jam.'
              : (result.errorMessage ?? 'Gagal kirim laporan.'),
        ),
        backgroundColor: result.ok ? const Color(0xFF059669) : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return result.ok;
  }

  Future<bool> _confirmBlock(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          authorName != null && authorName!.isNotEmpty
              ? 'Blokir $authorName?'
              : 'Blokir pengguna?',
        ),
        content: const Text(
          'Semua postingan, komentar, dan ulasan dari pengguna ini akan '
          'disembunyikan dari kamu. Bisa di-unblock kapan saja dari '
          'Pengaturan Akun.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Blokir'),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _ReasonPickerSheet extends StatelessWidget {
  final ReportTargetKind targetKind;

  const _ReasonPickerSheet({required this.targetKind});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Alasan laporkan ${targetKind.displayLabel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Pilih satu yang paling sesuai. Moderator Natalo akan tinjau dalam 24 jam.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: ReportReason.values.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                itemBuilder: (_, i) {
                  final reason = ReportReason.values[i];
                  return ListTile(
                    title: Text(
                      reason.displayLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF111827),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                    onTap: () => Navigator.of(context).pop(reason),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
