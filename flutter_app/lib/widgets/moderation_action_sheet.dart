import 'package:flutter/material.dart';

import '../services/block_service.dart';
import '../services/report_service.dart';
import 'app_toast.dart';

const _feedSheetSurface = Color(0xFF101114);
const _feedSheetDivider = Color(0xFF2A2B2F);
const _feedSheetHandle = Color(0xFF464A53);
const _feedSheetText = Color(0xFFFFFFFF);
const _feedSheetSubtext = Color(0xFFA3A3A3);

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

  /// User trigger self-delete (own comment / post) → caller harus
  /// optimistic remove dari list.
  final bool didDelete;

  const ModerationActionResult({
    this.didBlock = false,
    this.didReport = false,
    this.didDelete = false,
  });
}

/// Open bottom sheet dengan opsi report + block.
///
/// [authorId] dan [authorName] dipakai untuk block. Salah satu wajib
/// (preferensi ID kalau ada).
///
/// [allowSelfDelete] + [onSelfDelete]: kalau set true + callback, sheet
/// tampilkan opsi "Hapus" untuk user yang own konten. Caller wajib
/// pastikan kondisi own (mis. currentUserId == author.id). Callback
/// di-trigger setelah confirm dialog tapi SEBELUM sheet dismiss — caller
/// bertanggung jawab pop sheet kalau perlu setelah delete complete.
Future<ModerationActionResult?> showModerationActions(
  BuildContext context, {
  required ReportTargetKind targetKind,
  required String targetId,
  String? authorId,
  String? authorName,
  bool allowBlock = true,
  bool useFeedStyle = false,
  bool allowSelfDelete = false,
  Future<bool> Function()? onSelfDelete,
}) {
  return showModalBottomSheet<ModerationActionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: useFeedStyle ? 0.40 : 0.25),
    builder: (sheetContext) => _ModerationSheet(
      targetKind: targetKind,
      targetId: targetId,
      authorId: authorId,
      authorName: authorName,
      allowBlock: allowBlock,
      useFeedStyle: useFeedStyle,
      allowSelfDelete: allowSelfDelete,
      onSelfDelete: onSelfDelete,
    ),
  );
}

class _ModerationSheet extends StatelessWidget {
  final ReportTargetKind targetKind;
  final String targetId;
  final String? authorId;
  final String? authorName;
  final bool allowBlock;
  final bool useFeedStyle;
  final bool allowSelfDelete;
  final Future<bool> Function()? onSelfDelete;

  const _ModerationSheet({
    required this.targetKind,
    required this.targetId,
    this.authorId,
    this.authorName,
    required this.allowBlock,
    required this.useFeedStyle,
    this.allowSelfDelete = false,
    this.onSelfDelete,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = useFeedStyle ? _feedSheetSurface : Colors.white;
    final dividerColor =
        useFeedStyle ? _feedSheetDivider : const Color(0xFFF3F4F6);
    final handleColor =
        useFeedStyle ? _feedSheetHandle : const Color(0xFFD1D5DB);
    final labelColor = useFeedStyle ? _feedSheetText : const Color(0xFF111827);
    final subtitleColor =
        useFeedStyle ? _feedSheetSubtext : const Color(0xFF6B7280);
    final neutralIconColor =
        useFeedStyle ? _feedSheetSubtext : const Color(0xFF6B7280);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grip bar.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // Self-delete tile — owner-only. Tampil paling atas supaya
            // primary action mudah di-tap. Hide kalau bukan owner
            // (allowSelfDelete=false default).
            if (allowSelfDelete && onSelfDelete != null) ...[
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: const Color(0xFFEF4444),
                label: 'Hapus ${targetKind.displayLabel}',
                subtitle:
                    'Hapus permanen dari Natalo. Aksi ini tidak bisa di-undo.',
                labelColor: labelColor,
                subtitleColor: subtitleColor,
                onTap: () async {
                  final confirmed = await _confirmDelete(context);
                  if (!confirmed) return;
                  final ok = await onSelfDelete!.call();
                  if (!context.mounted) return;
                  final rootCtx =
                      Navigator.of(context, rootNavigator: true).context;
                  Navigator.of(context).pop(
                    ModerationActionResult(didDelete: ok),
                  );
                  if (ok) {
                    AppToast.showBanner(
                      rootCtx,
                      '${targetKind.displayLabel.toUpperCase().substring(0, 1)}${targetKind.displayLabel.substring(1)} dihapus.',
                      kind: ToastKind.success,
                    );
                  } else {
                    AppToast.showBanner(
                      rootCtx,
                      'Gagal hapus ${targetKind.displayLabel}. Coba lagi.',
                      kind: ToastKind.error,
                    );
                  }
                },
              ),
              Divider(height: 1, color: dividerColor),
            ],
            // Report tile — hide kalau ini own content (gak masuk akal
            // laporkan diri sendiri).
            if (!allowSelfDelete) ...[
              _ActionTile(
                icon: Icons.flag_outlined,
                iconColor: const Color(0xFFEF4444),
                label: 'Laporkan ${targetKind.displayLabel}',
                subtitle: 'Kirim ke moderator Natalo untuk ditinjau',
                labelColor: labelColor,
                subtitleColor: subtitleColor,
                onTap: () async {
                  final result = await _openReportFlow(context);
                  if (!context.mounted) return;
                  Navigator.of(context).pop(
                    ModerationActionResult(didReport: result),
                  );
                },
              ),
            ],
            if (allowBlock &&
                (authorId != null || (authorName?.isNotEmpty ?? false))) ...[
              Divider(height: 1, color: dividerColor),
              _ActionTile(
                icon: Icons.block_outlined,
                iconColor: neutralIconColor,
                label: authorName != null && authorName!.isNotEmpty
                    ? 'Blokir $authorName'
                    : 'Blokir pengguna ini',
                subtitle: 'Sembunyikan semua konten dari pengguna ini',
                labelColor: labelColor,
                subtitleColor: subtitleColor,
                onTap: () async {
                  final confirmed = await _confirmBlock(context);
                  if (!confirmed) return;
                  await blockService.blockUser(
                    userId: authorId,
                    userName: authorName,
                  );
                  if (!context.mounted) return;
                  final rootCtx =
                      Navigator.of(context, rootNavigator: true).context;
                  Navigator.of(context).pop(
                    const ModerationActionResult(didBlock: true),
                  );
                  AppToast.showBanner(
                    rootCtx,
                    authorName != null && authorName!.isNotEmpty
                        ? '$authorName diblokir. Konten dari pengguna ini disembunyikan.'
                        : 'Pengguna diblokir.',
                    kind: ToastKind.success,
                  );
                },
              ),
            ],
            Divider(height: 1, color: dividerColor),
            _ActionTile(
              icon: Icons.close_rounded,
              iconColor: neutralIconColor,
              label: 'Batal',
              labelColor: labelColor,
              subtitleColor: subtitleColor,
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
      barrierColor: Colors.black.withValues(alpha: useFeedStyle ? 0.40 : 0.25),
      builder: (_) => _ReasonPickerSheet(
        targetKind: targetKind,
        useFeedStyle: useFeedStyle,
      ),
    );
    if (reason == null) return false;
    if (!context.mounted) return false;
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
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    AppToast.showBanner(
      rootCtx,
      result.ok
          ? 'Laporan terkirim. Moderator akan meninjau dalam 24 jam.'
          : (result.errorMessage ?? 'Gagal kirim laporan.'),
      kind: result.ok ? ToastKind.success : ToastKind.error,
    );
    return result.ok;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Hapus ${targetKind.displayLabel}?'),
        content: Text(
          '${targetKind.displayLabel[0].toUpperCase()}${targetKind.displayLabel.substring(1)} '
          'akan dihapus permanen dan tidak bisa di-undo.',
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
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    return result == true;
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
  final bool useFeedStyle;

  const _ReasonPickerSheet({
    required this.targetKind,
    required this.useFeedStyle,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = useFeedStyle ? _feedSheetSurface : Colors.white;
    final dividerColor =
        useFeedStyle ? _feedSheetDivider : const Color(0xFFF3F4F6);
    final handleColor =
        useFeedStyle ? _feedSheetHandle : const Color(0xFFD1D5DB);
    final labelColor = useFeedStyle ? _feedSheetText : const Color(0xFF111827);
    final subtitleColor =
        useFeedStyle ? _feedSheetSubtext : const Color(0xFF6B7280);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Pilih satu yang paling sesuai. Moderator Natalo akan tinjau dalam 24 jam.',
                style: TextStyle(
                  fontSize: 13,
                  color: subtitleColor,
                ),
              ),
            ),
            Divider(height: 1, color: dividerColor),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: ReportReason.values.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: dividerColor),
                itemBuilder: (_, i) {
                  final reason = ReportReason.values[i];
                  return ListTile(
                    title: Text(
                      reason.displayLabel,
                      style: TextStyle(
                        fontSize: 15,
                        color: labelColor,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: useFeedStyle
                          ? _feedSheetSubtext
                          : const Color(0xFF9CA3AF),
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
  final Color labelColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.labelColor,
    required this.subtitleColor,
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: subtitleColor,
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
