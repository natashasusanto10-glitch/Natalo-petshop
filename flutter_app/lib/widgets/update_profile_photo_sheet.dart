import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../screens/profile_photo_picker_screen.dart';
import '../services/api_client.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../utils/read_only_mode.dart';
import '../widgets/photo_crop/photo_crop_export.dart';
import 'app_toast.dart';

const _brandBlue = NataloColors.primary;
const _dangerRed = Color(0xFFEF4444);

/// Bottom sheet "Ubah Foto Profil".
///
/// Munculkan via `showUpdateProfilePhotoSheet(context)`. Sheet menampilkan
/// 3 opsi:
/// 1. Ambil Foto (kamera)
/// 2. Pilih dari Galeri
/// 3. Hapus Foto (only kalau profile sudah punya photo)
/// plus Batal.
///
/// Setelah user pilih file, photo path disimpan ke `memberStore` via
/// `persistProfileUpdate()` → avatar di seluruh app refresh otomatis lewat
/// AnimatedBuilder yang listen memberStore.
///
/// **Scope sekarang local-only**: file path simpan ke profilePhotoUrl.
/// `ProfileAvatar` widget sudah support load via Image.file untuk path
/// local. Backend upload bisa di-tambah nanti tanpa ubah call site sheet.
Future<void> showUpdateProfilePhotoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetCtx) => const _UpdateProfilePhotoSheet(),
  );
}

class _UpdateProfilePhotoSheet extends StatefulWidget {
  const _UpdateProfilePhotoSheet();

  @override
  State<_UpdateProfilePhotoSheet> createState() =>
      _UpdateProfilePhotoSheetState();
}

class _UpdateProfilePhotoSheetState extends State<_UpdateProfilePhotoSheet> {
  final _picker = ImagePicker();
  bool _busy = false;

  bool get _hasExistingPhoto {
    final url = memberStore.profile?.profilePhotoUrl?.trim();
    return url != null && url.isNotEmpty;
  }

  /// Kamera — tanpa crop step (native picker 1024×1024), tapi tetap lewat
  /// re-encode JPEG bersama (bukan upload file mentah dari OS/OEM kamera).
  /// Beberapa device balikin format yang tak konsisten dgn MIME yang
  /// diklaim (mis. HEIC berlabel jpeg) → validasi magic-byte backend
  /// nolak "File foto tidak valid" secara acak. Re-encode di sini
  /// menjamin JPEG asli, sama seperti jalur galeri.
  Future<void> _pickFromCamera() async {
    if (_busy) return;
    AppHaptics.tap();
    setState(() => _busy = true);
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked == null) {
        // User batal — tutup sheet tanpa ubah apapun.
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      final tmpDir = await getTemporaryDirectory();
      // HEIC-safe: sama seperti jalur galeri (profile_photo_picker_screen).
      final normalizedPath = await normalizePhotoSourceToJpeg(
        picked.path,
        tmpDir.path,
        pathSeparator: Platform.pathSeparator,
      );
      final outPath = await compute(
        processPhotoInIsolate,
        PhotoProcessArgs(
          sourcePath: normalizedPath,
          tmpDirPath: tmpDir.path,
          targetAspect: 1.0,
          scale: 1.0,
          offsetFractionX: 0,
          offsetFractionY: 0,
          preserveOriginal: true, // skip crop — cuma bake orientation + JPEG.
          maxLongSide: 1024,
          jpegQuality: 88,
          timestampSuffix: 0,
          pathSeparator: Platform.pathSeparator,
        ),
      );
      await _uploadFile(outPath);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Galeri — buka full-screen picker Instagram-style (grid + crop lingkaran).
  /// User batal (pop null) → biarkan sheet terbuka. Dapat File → upload lewat
  /// jalur yang sama dengan kamera.
  Future<void> _pickFromGallery() async {
    if (_busy) return;
    AppHaptics.tap();
    final File? cropped = await ProfilePhotoPickerScreen.open(context);
    if (cropped == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _uploadFile(cropped.path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Upload + persist + toast/error — dipakai bersama jalur kamera & galeri
  /// supaya perilaku (sukses, ApiException, read-only, error umum) identik.
  Future<void> _uploadFile(String path) async {
    try {
      // Upload ke backend (UploadThing CDN) + auto-save URL ke
      // User.profilePhotoUrl. Backend return updated profile, langsung
      // sync ke memberStore supaya UI lain (Akun page, feed, comment)
      // refresh otomatis lewat AnimatedBuilder.
      final updated = await memberService.uploadProfilePhoto(path);
      final current = memberStore.profile;
      if (updated != null && current != null) {
        // Merge, JANGAN replace total — endpoint upload foto cuma
        // guarantee profilePhotoUrl segar; kalau backend/versi lama tak
        // ikut select field lain (username, bio, dst), replace total bikin
        // field itu kosong sesaat sampai halaman lain fetch ulang profil.
        await memberStore.persistProfileUpdate(
          current.copyWith(profilePhotoUrl: updated.profilePhotoUrl),
        );
      } else if (updated != null) {
        await memberStore.persistProfileUpdate(updated);
      } else if (current != null) {
        // Fallback ke local path kalau backend tidak return profile
        // (rare — biasanya backend error → throw exception).
        await memberStore.persistProfileUpdate(
          current.copyWith(profilePhotoUrl: path),
        );
      }
      if (!mounted) return;
      AppHaptics.success();
      Navigator.of(context).maybePop();
      AppToast.show(
        context,
        'Foto profil berhasil diperbarui.',
        kind: ToastKind.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Upload foto gagal: ${error.message}',
        kind: ToastKind.error,
      );
    } on ReadOnlyModeException {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Mode aman aktif. Upload foto belum bisa dilakukan.',
        kind: ToastKind.warning,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Gagal upload foto: $error',
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _removePhoto() async {
    if (_busy) return;
    AppHaptics.warning();
    setState(() => _busy = true);
    try {
      // Hapus di backend dulu — set User.profilePhotoUrl ke null.
      await memberService.deleteProfilePhoto();
      // Sync ke local memberStore.
      final current = memberStore.profile;
      if (current != null) {
        final updated = current.copyWith(clearProfilePhoto: true);
        await memberStore.persistProfileUpdate(updated);
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
      AppToast.show(
        context,
        'Foto profil dihapus.',
        kind: ToastKind.success,
      );
    } on ReadOnlyModeException {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Mode aman aktif. Hapus foto belum bisa dilakukan.',
        kind: ToastKind.warning,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      AppToast.show(
        context,
        'Gagal hapus foto: $error',
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle.
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Ubah Foto Profil',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pilih foto terbaik agar akun Natalo kamu lebih mudah dikenali.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          _PhotoActionTile(
            icon: Icons.photo_camera_rounded,
            iconColor: _brandBlue,
            iconBg: isDark
                ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                : const Color(0xFFEAF5FF),
            title: 'Ambil Foto',
            subtitle: 'Buka kamera dan ambil foto baru',
            onTap: _busy ? null : _pickFromCamera,
          ),
          const SizedBox(height: 8),
          _PhotoActionTile(
            icon: Icons.photo_library_rounded,
            iconColor: const Color(0xFF22C55E),
            iconBg: const Color(0xFFE8F8EC),
            title: 'Pilih dari Galeri',
            subtitle: 'Atur & potong foto sebelum dipakai',
            onTap: _busy ? null : _pickFromGallery,
          ),
          if (_hasExistingPhoto) ...[
            const SizedBox(height: 8),
            _PhotoActionTile(
              icon: Icons.delete_outline_rounded,
              iconColor: _dangerRed,
              iconBg: const Color(0xFFFEE2E2),
              title: 'Hapus Foto',
              subtitle: 'Kembali ke avatar huruf awal nama',
              titleColor: _dangerRed,
              onTap: _busy ? null : _removePhoto,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Batal'),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(_brandBlue),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _PhotoActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: disabled ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor ?? cs.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (titleColor == null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
