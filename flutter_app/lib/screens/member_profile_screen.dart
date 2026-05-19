import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  DateTime? _birthDate;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final profile = memberStore.profile;
    _nameController = TextEditingController(text: profile?.name ?? '')
      ..addListener(_markDirty);
    _emailController = TextEditingController(text: profile?.email ?? '')
      ..addListener(_markDirty);
    _phoneController = TextEditingController(text: profile?.phone ?? '')
      ..addListener(_markDirty);
    _birthDate = profile?.birthDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
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
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      AppHaptics.warning();
      AppToast.show(context, 'Nama tidak boleh kosong.', kind: ToastKind.error);
      return;
    }
    if (email.isNotEmpty && !email.contains('@')) {
      AppHaptics.warning();
      AppToast.show(context, 'Format email tidak valid.', kind: ToastKind.error);
      return;
    }

    AppHaptics.tap();
    setState(() => _saving = true);
    try {
      final updated = await memberService.updateProfile(
        name: name,
        email: email.isEmpty ? null : email,
        phone: phone.isEmpty ? null : phone,
        birthDate: _birthDate,
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
              email: email.isEmpty ? null : email,
              phone: phone.isEmpty ? null : phone,
              birthDate: _birthDate,
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
                        _ProfileFormField(
                          label: 'Email',
                          controller: _emailController,
                          icon: Icons.email_rounded,
                          iconColor: const Color(0xFF22C55E),
                          iconBg: const Color(0xFFE8F8EC),
                          hint: 'nama@email.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const _FormDivider(),
                        _ProfileFormField(
                          label: 'Nomor WhatsApp',
                          controller: _phoneController,
                          icon: Icons.phone_iphone_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          iconBg: const Color(0xFFF3E8FF),
                          hint: '08xxxxxxxxxx',
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d+\s-]'),
                            ),
                            LengthLimitingTextInputFormatter(20),
                          ],
                        ),
                        const _FormDivider(),
                        _BirthDatePickerTile(
                          birthDate: _birthDate,
                          onTap: _pickBirthDate,
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
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  const _ProfileFormField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  textCapitalization: textCapitalization,
                  inputFormatters: inputFormatters,
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
