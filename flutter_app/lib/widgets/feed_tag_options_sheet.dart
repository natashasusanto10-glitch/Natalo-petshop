import 'package:flutter/material.dart';
import '../constants/official_brand.dart';
import '../models/feed_post.dart';
import '../services/feed_service.dart';
import '../theme/natalo_colors.dart';
import 'app_toast.dart';
import 'official_brand_avatar.dart';
import 'profile_avatar.dart';

/// Grip bar ala IG di atas bottom sheet — penanda visual sheet bisa
/// di-drag/ditutup (audit polish Spec B).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 2),
      decoration: BoxDecoration(
        color: NataloColors.grey300,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Sheet "Opsi Tag" untuk nama sendiri (Spec B Task 12). onRemoved dipanggil
/// SEBELUM await network selesai (optimistic — pill/baris hilang seketika).
/// Kalau network gagal, [onRemoveFailed] dipanggil supaya pemanggil
/// mengembalikan pill/baris yang sudah dibuang (rollback).
Future<void> showFeedTagOptionsSheet(
  BuildContext context, {
  required String postId,
  required bool hidden,
  required VoidCallback onRemoved,
  required ValueChanged<bool> onHiddenChanged,
  VoidCallback? onRemoveFailed,
  Future<void> Function(String postId)? removeTag,
  Future<void> Function(String postId, bool hidden)? setHidden,
}) {
  final doRemove = removeTag ?? feedService.removeMyTag;
  final doSetHidden = setHidden ?? feedService.setMyTagHidden;
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Opsi Tag',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_remove_outlined,
                color: NataloColors.danger,
              ),
              title: const Text(
                'Hapus saya dari post',
                style: TextStyle(color: NataloColors.danger),
              ),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: sheetContext,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Hapus tag?'),
                    content: const Text(
                      'Kamu tidak akan ditandai lagi di postingan ini.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text(
                          'Hapus',
                          style: TextStyle(color: NataloColors.danger),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                // Optimistic: pill/baris hilang SEKETIKA, network menyusul.
                onRemoved();
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                try {
                  await doRemove(postId);
                } catch (_) {
                  // Rollback — kembalikan pill/baris yang tadi dibuang.
                  onRemoveFailed?.call();
                  if (context.mounted) {
                    AppToast.showBanner(
                      context,
                      'Gagal menghapus tag. Coba lagi.',
                      kind: ToastKind.error,
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(
                hidden
                    ? 'Tampilkan di profil saya'
                    : 'Sembunyikan dari profil saya',
              ),
              onTap: () async {
                final next = !hidden;
                onHiddenChanged(next);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                try {
                  await doSetHidden(postId, next);
                } catch (_) {
                  onHiddenChanged(!next); // rollback
                  if (context.mounted) {
                    AppToast.showBanner(
                      context,
                      'Gagal menyimpan. Coba lagi.',
                      kind: ToastKind.error,
                    );
                  }
                }
              },
            ),
            ListTile(
              title: const Center(child: Text('Batal')),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      );
    },
  );
}

/// Sheet video "Ditandai dalam video ini" — satu-satunya surface tag utk
/// video (spec §3, wajib ada).
Future<void> showFeedTaggedUsersSheet(
  BuildContext context, {
  required FeedPost post,
  required String? selfUserId,
  required VoidCallback onSelfRemoved,
  required ValueChanged<bool> onSelfHiddenChanged,
  VoidCallback? onSelfRemoveFailed,
  // Server kirim state hidden per-viewer via FeedPost.viewerTagHidden
  // (final review Spec B fix) — pemanggil seed dari situ di initState
  // (bukan hardcoded false), lalu melacak toggle in-session di atasnya
  // supaya label sheet Opsi Tag akurat baik di initial build maupun
  // setelah toggle.
  bool selfHidden = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Ditandai dalam video ini',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final tag in post.taggedUsers)
                    ListTile(
                      // Server null-kan foto asli akun official/admin (brand
                      // guard, lib/social/brand-user.ts) — klien WAJIB render
                      // logo brand lokal, sama seperti avatar author/likers/
                      // komentar di tempat lain (feed_post_shared_widgets.dart).
                      leading: tag.name == kOfficialBrandName
                          ? const OfficialBrandAvatar(size: 40)
                          : ProfileAvatar(
                              initial: (tag.name.isNotEmpty
                                      ? tag.name
                                      : (tag.username ?? '?'))
                                  .characters
                                  .first
                                  .toUpperCase(),
                              imageUrl: tag.profilePhotoUrl,
                              size: 40,
                              fontSize: 16,
                            ),
                      title: Text(
                        tag.name.isNotEmpty ? tag.name : (tag.username ?? ''),
                      ),
                      subtitle: tag.username == null
                          ? null
                          : Text('@${tag.username}'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (tag.userId == selfUserId) {
                          // Baris nama sendiri → pintu Opsi Tag yang sama.
                          showFeedTagOptionsSheet(
                            context,
                            postId: post.id,
                            hidden: selfHidden,
                            onRemoved: onSelfRemoved,
                            onHiddenChanged: onSelfHiddenChanged,
                            onRemoveFailed: onSelfRemoveFailed,
                          );
                        } else if (tag.username != null &&
                            tag.username!.isNotEmpty) {
                          Navigator.of(context)
                              .pushNamed('/u', arguments: tag.username);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
