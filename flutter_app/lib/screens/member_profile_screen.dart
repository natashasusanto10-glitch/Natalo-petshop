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
  /// Snapshot lock state dari profile saat load. Render read-only kalau
  /// non-null. Lihat MemberProfile.birthDateLockedAt — diset server saat
  /// user dapat voucher ultah pertama (anti-abuse).
  DateTime? _birthDateLockedAt;
  bool _saving = false;
  bool _dirty = false;

  static const int _bioMaxLength = 150;

  bool get _isBirthDateLocked => _birthDateLockedAt != null;

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
    _birthDateLockedAt = profile?.birthDateLockedAt;
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
    // Defensive guard — UI sudah hide tap target kalau locked, tapi
    // double check supaya kalau ada path lain yang call method ini,
    // tidak buka picker secara salah.
    if (_isBirthDateLocked) return;

    // Warning dialog SEBELUM date picker — user perlu sadar bahwa
    // tgl lahir akan terkunci permanen setelah save (Opsi B Shopee
    // strict). Confirmation ini critical karena:
    //   - Salah input = harus WA admin untuk koreksi (effort)
    //   - Setelah locked = TIDAK BISA edit sendiri di app
    //
    // Dialog hanya muncul kalau user belum pernah set birthDate
    // (_birthDate == null) — kalau sudah ada birthDate tapi unlocked
    // (kasus rare: setelah admin override), skip dialog karena user
    // memang request edit.
    final isFirstTimeSet = _birthDate == null;
    if (isFirstTimeSet) {
      AppHaptics.tap();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6CC),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xFFFBBF24),
              size: 28,
            ),
          ),
          title: const Text(
            'Tanggal lahir akan terkunci',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Setelah kamu pilih dan simpan tanggal lahir, tanggal '
                'akan TERKUNCI dan tidak bisa kamu ubah sendiri.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(dialogCtx).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Kalau salah input nanti, kamu harus hubungi admin via '
                'WhatsApp untuk ralat. Pastikan tanggal yang kamu pilih '
                'sudah BENAR.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
              ),
              child: const Text('Lanjut'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      // Re-check mounted setelah dialog dismiss — async gap.
      if (!mounted) return;
    }

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
              onSurface: Color(0xFF101828),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      // Page bg off-white (#F7FAFF light) seperti semula — pakai
      // scaffoldBackgroundColor, BUKAN cs.surface (putih) yang bikin kartu
      // putih hilang kontras.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Kembali',
        ),
        title: Text(
          'Ubah Profil',
          style: TextStyle(
            color: cs.onSurface,
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Sesi habis. Silakan login ulang.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
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
                        Text(
                          'Tap foto untuk mengubah',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
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
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
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
                          iconBg: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                              : const Color(0xFFEAF5FF),
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
                        // Acquisition nudge — banner kuning muncul kalau
                        // user belum set tgl lahir + belum locked. Jelas
                        // value prop "isi → dapat voucher". Tap → trigger
                        // picker (sama dengan tap tile). Hilang setelah
                        // user set tgl lahir.
                        if (_birthDate == null && !_isBirthDateLocked)
                          _BirthdayPromoBanner(onTap: _pickBirthDate),
                        _BirthDatePickerTile(
                          birthDate: _birthDate,
                          onTap: _pickBirthDate,
                          isLocked: _isBirthDateLocked,
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
    final cs = Theme.of(context).colorScheme;
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
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
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
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant,
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
                        ? TextStyle(
                            color: cs.onSurfaceVariant,
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

/// Banner promo "isi tgl lahir = dapat voucher Rp50k" — onboarding nudge
/// di Profile screen. Tampil hanya kalau user belum set tgl lahir dan
/// belum locked (kebanyakan kasus = user baru / customer lama yang skip
/// fill saat register).
///
/// Tap → langsung trigger picker flow yang sama dengan tile bawah,
/// supaya user gak perlu scroll dan tahu apa yang harus di-tap.
class _BirthdayPromoBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _BirthdayPromoBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: const Color(0xFFFFF6CC),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.4),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      '🎁',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Dapat voucher Rp50.000 saat ulang tahun!',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Isi tanggal lahir kamu sekarang.',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB45309),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BirthDatePickerTile extends StatelessWidget {
  final DateTime? birthDate;
  final VoidCallback onTap;
  /// Kalau true, tile render read-only dengan lock icon + hint
  /// "Hubungi admin untuk ubah". User TIDAK bisa tap untuk buka picker.
  /// Triggered server-side setelah voucher ulang tahun pertama issued
  /// (anti-abuse — cegah user ganti2 tgl lahir farm voucher).
  final bool isLocked;

  const _BirthDatePickerTile({
    required this.birthDate,
    required this.onTap,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDate = birthDate != null;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isLocked
                  ? cs.surfaceContainerHighest
                  : const Color(0xFFFFF6CC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isLocked ? Icons.lock_outline_rounded : Icons.cake_rounded,
              color: isLocked
                  ? cs.onSurfaceVariant
                  : const Color(0xFFFBBF24),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Tanggal Lahir',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (isLocked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'TERKUNCI',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hasDate ? _formatBirthDate(birthDate!) : 'Belum diatur',
                  style: TextStyle(
                    color: hasDate ? cs.onSurface : cs.onSurfaceVariant,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isLocked) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Hubungi admin via WhatsApp untuk ubah.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (!hasDate) ...[
                  // Hint kalau belum di-set — warn user bahwa setelah save
                  // akan ke-lock. Kombinasi dengan confirm dialog di
                  // _pickBirthDate supaya user double-aware sebelum commit.
                  const SizedBox(height: 4),
                  const Text(
                    'Akan terkunci setelah disimpan.',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isLocked)
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant,
            ),
        ],
      ),
    );
    // Locked state: no InkWell — tile non-interactive supaya gak ada
    // ripple yang bikin user mikir bisa diklik.
    if (isLocked) return content;
    return InkWell(onTap: onTap, child: content);
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
    final cs = Theme.of(context).colorScheme;
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
                  Text(
                    'Username',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
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
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
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
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
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
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Email dan nomor WhatsApp dikunci setelah pendaftaran '
                'untuk mencegah penyalahgunaan voucher 1× pakai.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Kalau kamu butuh ganti (mis. pindah nomor, typo saat '
                'daftar), hubungi admin lewat WhatsApp dengan menyertakan '
                'data lama + data baru.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
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
                  foregroundColor: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
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
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
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
                    style: TextStyle(
                      color: cs.onSurface,
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
            Icon(
              Icons.lock_outline_rounded,
              color: cs.onSurfaceVariant,
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
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      // Divider antar-field sengaja super halus di light (#EFF2F6) seperti
      // semula; dark pakai border gelap.
      child: Divider(
        height: 1,
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.outlineVariant
            : const Color(0xFFEFF2F6),
      ),
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
