import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/natalo_store_config.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/update_profile_photo_sheet.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _darkNavy = Color(0xFF101828);
const _textSecondary = Color(0xFF667085);
const _pageBg = Color(0xFFF7FAFF);
const _borderSoft = Color(0xFFE0E7F0);

/// Focused EditProfile form.
///
/// Per spec "Revisi Flutter — Simplify Akun menjadi 2 Halaman":
/// Halaman ini BUKAN dashboard akun. Hanya form untuk edit data pribadi:
/// - Foto profil (tap → bottom sheet "Ubah Foto Profil")
/// - Nama lengkap
/// - Email
/// - Nomor HP / WhatsApp
/// - Tanggal lahir
///
/// Tidak lagi menampilkan aktivitas, voucher, poin, postingan, atau logout.
/// Dashboard sudah dipindah ke [MemberScreen] (Akun page), logout dipindah
/// ke [AccountSettingsScreen] (Pengaturan).
///
/// Route tetap `/member/profile` untuk back-compat — semua tempat yang
/// previously navigate ke sini (mis. settings → "Ubah Profil") sekarang
/// dapat form yang focused, bukan halaman besar duplikatif.
class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({super.key});

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  DateTime? _birthDate;
  bool _saving = false;
  bool _dirty = false;

  static const int _bioMaxLength = 150;

  @override
  void initState() {
    super.initState();
    final profile = memberStore.profile;
    _nameController = TextEditingController(text: profile?.name ?? '')
      ..addListener(_markDirty);
    // Email + phone DI-LOCK — display only via _LockedInfoTile. Tidak
    // ada controller karena bukan TextField.
    _bioController = TextEditingController(text: profile?.bio ?? '')
      ..addListener(_markDirty);
    _birthDate = profile?.birthDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  bool get _canSave => _dirty && !_saving;

  Future<void> _pickBirthDate() async {
    AppHaptics.tap();
    final now = DateTime.now();
    final initial =
        _birthDate ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _brandBlue,
              onPrimary: Colors.white,
              onSurface: _darkNavy,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _brandBlue),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();

    if (name.isEmpty) {
      AppHaptics.warning();
      AppToast.show(context, 'Nama tidak boleh kosong.', kind: ToastKind.error);
      return;
    }
    if (bio.length > _bioMaxLength) {
      AppHaptics.warning();
      AppToast.show(
        context,
        'Bio maksimal $_bioMaxLength karakter.',
        kind: ToastKind.error,
      );
      return;
    }

    AppHaptics.tap();
    setState(() => _saving = true);
    try {
      // Email + phone TIDAK dikirim — locked di UI (Option C anti voucher
      // abuse, lihat _LockedInfoTile di bawah). Backend /api/auth/me PATCH
      // juga ignore field email/phone dari customer session sebagai
      // belt-and-suspenders.
      final updated = await memberService.updateProfile(
        name: name,
        birthDate: _birthDate,
        bio: bio.isEmpty ? null : bio,
        clearBio: bio.isEmpty,
      );
      if (updated != null) {
        // Preserve foto profil local kalau ada — server biasanya tidak return
        // field profilePhotoUrl pada response /api/auth/me PATCH ini.
        final preserved = updated.copyWith(
          profilePhotoUrl: memberStore.profile?.profilePhotoUrl,
        );
        await memberStore.persistProfileUpdate(preserved);
      } else {
        // Server null = update belum support / fail silent — tetap update local
        // supaya UX tidak terblokir.
        final current = memberStore.profile;
        if (current != null) {
          await memberStore.persistProfileUpdate(
            current.copyWith(
              name: name,
              birthDate: _birthDate,
              bio: bio.isEmpty ? null : bio,
              clearBio: bio.isEmpty,
            ),
          );
        }
      }
      if (!mounted) return;
      AppHaptics.success();
      setState(() {
        _saving = false;
        _dirty = false;
      });
      AppToast.show(
        context,
        'Profil berhasil diperbarui.',
        kind: ToastKind.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      setState(() => _saving = false);
      AppToast.show(
        context,
        'Gagal menyimpan: $error',
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _darkNavy),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Kembali',
        ),
        title: const Text(
          'Ubah Profil',
          style: TextStyle(
            color: _darkNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: memberStore,
        builder: (context, _) {
          final profile = memberStore.profile;
          if (profile == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Sesi habis. Silakan login ulang.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSecondary, fontSize: 14),
                ),
              ),
            );
          }
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                children: [
                  // ── Avatar section (tappable → update photo sheet) ──
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Column(
                      children: [
                        ProfileAvatar(
                          initial: profile.initial,
                          imageUrl: profile.profilePhotoUrl,
                          size: 96,
                          fontSize: 36,
                          showCameraBadge: true,
                          onTap: () {
                            AppHaptics.tap();
                            showUpdateProfilePhotoSheet(context);
                          },
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tap foto untuk mengubah',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // ── Form fields card ──
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _borderSoft),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Username tile — public handle @kamu untuk feed/
                        // komentar + URL profile. Diletakkan paling atas
                        // (match IG/TikTok edit profile pattern) supaya
                        // jadi first impression user. Tap → buka dedicated
                        // setup screen dengan live availability check.
                        // Tidak bundled dengan tombol "Simpan Profil" di
                        // bawah karena flow-nya butuh validation server-
                        // side terpisah.
                        AnimatedBuilder(
                          animation: memberStore,
                          builder: (context, _) {
                            final username =
                                memberStore.profile?.username;
                            return _UsernameTile(
                              username: username,
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/member/username',
                              ),
                            );
                          },
                        ),
                        const _FormDivider(),
                        _ProfileFormField(
                          label: 'Nama Lengkap',
                          controller: _nameController,
                          icon: Icons.person_rounded,
                          iconColor: const Color(0xFF0B7FEA),
                          iconBg: const Color(0xFFEAF5FF),
                          hint: 'Masukkan nama lengkap',
                          textCapitalization: TextCapitalization.words,
                        ),
                        const _FormDivider(),
                        // Email + Nomor WhatsApp DI-LOCK display-only (Option C
                        // dari diskusi anti voucher-abuse). Identifier unique
                        // di DB — kalau user ganti, lama jadi free → bisa
                        // di-claim ulang lewat akun baru → multi-claim voucher
                        // 1×/user. Lock di UI = block 90% kasus tanpa
                        // implementasi cooldown flow yang kompleks. Untuk
                        // legitimate change, user hubungi admin via WA.
                        _LockedInfoTile(
                          label: 'Email',
                          value: memberStore.profile?.email ?? '—',
                          icon: Icons.email_rounded,
                          iconColor: const Color(0xFF22C55E),
                          iconBg: const Color(0xFFE8F8EC),
                        ),
                        const _FormDivider(),
                        _LockedInfoTile(
                          label: 'Nomor WhatsApp',
                          value: memberStore.profile?.phone ?? '—',
                          icon: Icons.phone_iphone_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          iconBg: const Color(0xFFF3E8FF),
                        ),
                        const _FormDivider(),
                        _BirthDatePickerTile(
                          birthDate: _birthDate,
                          onTap: _pickBirthDate,
                        ),
                        const _FormDivider(),
                        // Bio field — multiline text, max 150 char (IG conv).
                        // Live counter di kanan bawah supaya user paham
                        // berapa karakter tersisa. Pakai _ProfileFormField
                        // dengan extras `multiline` + `maxLength` supaya
                        // visual consistent dengan field lain.
                        _ProfileFormField(
                          label: 'Bio',
                          controller: _bioController,
                          icon: Icons.short_text_rounded,
                          iconColor: const Color(0xFFEC4899),
                          iconBg: const Color(0xFFFCE7F3),
                          hint: 'Tulis bio singkat (max $_bioMaxLength karakter)',
                          maxLines: 3,
                          minLines: 2,
                          maxLength: _bioMaxLength,
                          showCounter: true,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _canSave ? _save : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFD1D5DB),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Simpan Perubahan'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form field tile — icon left + label/value column right, edit inline
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String hint;
  final TextCapitalization textCapitalization;
  /// Multiline support — defaults to 1 line. Pass `maxLines: 3` untuk
  /// textarea-style field (mis. bio). `minLines` opsional supaya field
  /// start tinggi tertentu (anchor expand bottom-up).
  final int maxLines;
  final int? minLines;
  /// Maksimum karakter input — soft-limit via TextField.maxLength.
  /// Validation tetap di submit handler (caller's _save method) supaya
  /// pesan error consistent.
  final int? maxLength;
  /// Show counter "N / max" di kanan bawah field — IG-style untuk bio.
  /// Auto-hide kalau maxLength null. Pakai TextField built-in counter
  /// dengan style match design.
  final bool showCounter;

  const _ProfileFormField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.hint,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.showCounter = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
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
                  label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                TextField(
                  controller: controller,
                  keyboardType: maxLines > 1 ? TextInputType.multiline : null,
                  textCapitalization: textCapitalization,
                  maxLines: maxLines,
                  minLines: minLines,
                  maxLength: maxLength,
                  style: const TextStyle(
                    color: _darkNavy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: Color(0xFFB6BEC9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    // Hide built-in counter kalau showCounter false (default).
                    // Untuk bio, kita pakai default counter Flutter (kanan
                    // bawah, format "n / max"). Default style match design.
                    counterText: showCounter ? null : '',
                    counterStyle: showCounter
                        ? const TextStyle(
                            color: _textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthDatePickerTile extends StatelessWidget {
  final DateTime? birthDate;
  final VoidCallback onTap;

  const _BirthDatePickerTile({required this.birthDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasDate = birthDate != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6CC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.cake_rounded,
                color: Color(0xFFFBBF24),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tanggal Lahir',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasDate ? _formatBirthDate(birthDate!) : 'Belum diatur',
                    style: TextStyle(
                      color: hasDate ? _darkNavy : const Color(0xFFB6BEC9),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Username row — visual match _BirthDatePickerTile (tile pattern,
/// bukan inline form field) karena set/change username butuh flow
/// validation tersendiri (live availability check + reservation 30
/// hari) yang tidak cocok bundled dengan "Simpan Profil".
class _UsernameTile extends StatelessWidget {
  final String? username;
  final VoidCallback onTap;

  const _UsernameTile({required this.username, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasUsername = username != null && username!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.alternate_email_rounded,
                color: Color(0xFF0369A1),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Username',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasUsername ? username! : 'Belum diatur',
                    style: TextStyle(
                      color: hasUsername
                          ? _darkNavy
                          : const Color(0xFFB6BEC9),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (!hasUsername)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'BARU',
                  style: TextStyle(
                    color: Color(0xFF0369A1),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only display tile dengan padlock indicator. Email + Nomor
/// WhatsApp pake ini — visual sama dengan _ProfileFormField tapi TIDAK
/// editable. Tap → bottom sheet jelaskan kenapa, plus tombol Hubungi
/// Admin via WhatsApp untuk legitimate change request.
///
/// Rationale: identifier @unique di DB. Kalau user ganti, lama jadi
/// free → bisa dipake daftar baru → exploit voucher 1×/user. Lock UI
/// = pencegahan 90% kasus dengan effort minimal. Implementasi cooldown
/// flow proper bisa ditambah nanti kalau perlu (Option B di doc).
class _LockedInfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const _LockedInfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  void _showInfoSheet(BuildContext context) {
    AppHaptics.tap();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.viewPaddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 16 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ganti $label',
                      style: const TextStyle(
                        color: _darkNavy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Email dan nomor WhatsApp dikunci setelah pendaftaran '
                'untuk mencegah penyalahgunaan voucher 1× pakai.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Kalau kamu butuh ganti (mis. pindah nomor, typo saat '
                'daftar), hubungi admin lewat WhatsApp dengan menyertakan '
                'data lama + data baru.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    AppHaptics.tap();
                    final uri = NataloStoreConfig.whatsappUri(
                      message:
                          'Halo admin Natalo, saya butuh bantuan ganti '
                          '$label akun saya.',
                    );
                    final ok = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.of(ctx).maybePop();
                    } else {
                      AppToast.show(
                        ctx,
                        'Tidak bisa buka WhatsApp.',
                        kind: ToastKind.error,
                      );
                    }
                  },
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text('Hubungi Admin via WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).maybePop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  foregroundColor: _textSecondary,
                ),
                child: const Text(
                  'Tutup',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showInfoSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
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
                    label,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _darkNavy,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Padlock indicator — visual cue "locked tapi tetap
            // interaktif (tap untuk info + admin contact)".
            const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xFF94A3B8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormDivider extends StatelessWidget {
  const _FormDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 66),
      child: Divider(height: 1, color: Color(0xFFEFF2F6)),
    );
  }
}

String _formatBirthDate(DateTime date) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
