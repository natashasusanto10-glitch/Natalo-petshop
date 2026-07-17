import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/action_throttle.dart';
import '../utils/haptics.dart';
import '../utils/phone_formatter.dart';

/// SharedPreferences key untuk store deadline cooldown OTP resend.
/// Value = `DateTime.millisecondsSinceEpoch` saat cooldown habis. Dipakai
/// untuk restore countdown saat user balik ke register screen setelah
/// navigate away atau app cold-restart selama cooldown masih berjalan.
///
/// Auto-clear saat:
/// - Countdown reach 0 (timer tick clear).
/// - Register success step 2 (akun jadi).
/// - Stale (deadline sudah lewat saat dibaca).
const _kRegisterOtpCooldownKey = 'register_otp_resend_until_ms';

const _brandBlue = NataloColors.primary;
const _brandBlueDark = Color(0xFF075FCC);
const _softBlueCard = Color(0xFFEAF5FF);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _otpSent = false; // step 1 sukses → tampilkan field OTP
  // #3 inline validation: error per-field (null = tidak ada error). Diisi
  // saat _validate(), di-clear saat user mulai mengetik di field tsb.
  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _passwordError;
  String? _otpError;
  // Resend OTP countdown — disabled selama N detik setelah kirim OTP
  // supaya user tidak spam request. Reset ke 60 setiap kali OTP terkirim
  // (step 1 sukses + resend tap). 0 = enabled, >0 = disabled (display "Xs").
  int _resendCountdown = 0;
  Timer? _resendTimer;
  bool _resendingOtp = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _nameController,
      _emailController,
      _phoneController,
      _passwordController,
      _otpController,
    ]) {
      controller.addListener(_onFormChanged);
    }
    // Restore cooldown dari SharedPreferences kalau ada deadline yang
    // masih in-future. Handle edge case: user kill app saat cooldown,
    // reopen dalam window 60s → countdown auto-resume dari nilai sisa
    // (tidak reset ke 0 + tidak boost user bisa spam langsung).
    _restoreCountdownFromPrefs();
  }

  Future<void> _restoreCountdownFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_kRegisterOtpCooldownKey) ?? 0;
      if (until <= 0) return;
      final remainingMs = until - DateTime.now().millisecondsSinceEpoch;
      if (remainingMs <= 1000) {
        // Cooldown sudah lewat → cleanup stale value.
        await prefs.remove(_kRegisterOtpCooldownKey);
        return;
      }
      if (!mounted) return;
      final remainingSeconds = (remainingMs / 1000).round();
      setState(() => _resendCountdown = remainingSeconds);
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_resendCountdown <= 1) {
          t.cancel();
          setState(() => _resendCountdown = 0);
          try {
            final p = await SharedPreferences.getInstance();
            await p.remove(_kRegisterOtpCooldownKey);
          } catch (_) {}
        } else {
          setState(() => _resendCountdown -= 1);
        }
      });
    } catch (_) {
      // Disk read fail → silent, cooldown stay at 0.
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _emailController,
      _phoneController,
      _passwordController,
      _otpController,
    ]) {
      controller.removeListener(_onFormChanged);
    }
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  /// Start 60-second cooldown setelah OTP terkirim (step 1 sukses atau
  /// resend tap). Selama countdown >0, button resend disabled +
  /// tampilkan "Tunggu Xs". Timer.periodic 1 detik, auto-cancel saat 0.
  ///
  /// Persist deadline ke SharedPreferences supaya kalau user navigate
  /// keluar / app cold-restart selama cooldown, balik ke screen ini
  /// countdown auto-resume (tidak reset).
  Future<void> _startResendCooldown() async {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    // Tulis deadline ke prefs SEBELUM timer mulai — supaya kalau widget
    // di-dispose mid-tick, value tetap ada di disk untuk restore.
    final deadlineMs = DateTime.now().millisecondsSinceEpoch + 60 * 1000;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kRegisterOtpCooldownKey, deadlineMs);
    } catch (_) {
      // Disk write fail → in-memory cooldown tetap jalan. Tidak block UX.
    }
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        t.cancel();
        setState(() => _resendCountdown = 0);
        // Cleanup disk value setelah cooldown selesai.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kRegisterOtpCooldownKey);
        } catch (_) {}
      } else {
        setState(() => _resendCountdown -= 1);
      }
    });
  }

  /// Resend OTP — panggil register endpoint mode step-1 (otp=null) supaya
  /// backend generate + kirim ulang kode. Reset cooldown setelah sukses.
  Future<void> _resendOtp() async {
    if (_resendCountdown > 0 || _resendingOtp) return;
    AppHaptics.tap();
    setState(() => _resendingOtp = true);
    try {
      final phoneRaw = _phoneController.text.replaceAll(RegExp(r'[^\d+]'), '');
      await authService.register(
        name: _nameController.text,
        // username tidak dikirim — server auto-generate dari nama.
        email: _emailController.text,
        phone: phoneRaw,
        password: _passwordController.text,
        otp: null, // null = step 1, kirim OTP baru
      );
      if (!mounted) return;
      AppHaptics.success();
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kode OTP baru sudah dikirim ke email & WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyRegisterError(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _resendingOtp = false);
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasValidEmail {
    final email = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _hasValidPhone =>
      _phoneController.text.replaceAll(RegExp(r'[^\d]'), '').length >= 8;

  bool get _canSubmit {
    final baseValid = _nameController.text.trim().isNotEmpty &&
        _hasValidEmail &&
        _hasValidPhone &&
        _passwordController.text.length >= 8;

    if (!_otpSent) return baseValid;
    // #6: konsisten dengan login OTP & hint "6 digit" — wajib tepat 6.
    return baseValid && _otpController.text.trim().length == 6;
  }

  Future<void> _onPrimary() async {
    AppHaptics.tap();
    if (!_validate()) return;
    setState(() => _loading = true);
    try {
      // Strip non-digit dari phone — PhoneFormatter kasih dash buat readable,
      // tapi backend expect digit format (+62812... atau 0812...).
      final phoneRaw = _phoneController.text.replaceAll(RegExp(r'[^\d+]'), '');
      final result = await authService.register(
        name: _nameController.text,
        // username tidak dikirim — server auto-generate dari nama.
        email: _emailController.text,
        phone: phoneRaw,
        password: _passwordController.text,
        otp: _otpSent ? _otpController.text : null,
      );
      if (!mounted) return;

      if (result == null) {
        // Step 1 sukses — OTP terkirim. Start 60s cooldown supaya user
        // tidak bisa spam resend langsung; button "Kirim Ulang Kode" baru
        // bisa di-tap setelah countdown selesai.
        AppHaptics.success();
        setState(() => _otpSent = true);
        _startResendCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kode OTP dikirim ke email dan WhatsApp kamu. Masukkan satu kode yang sama.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Step 2 sukses — user dibuat. User tetap login manual supaya session
      // dan cart sync memakai flow login member yang sama.
      AppHaptics.success();
      // Cleanup cooldown pref — flow register selesai, cooldown OTP
      // resend tidak relevan lagi. Cancel timer juga untuk safety.
      _resendTimer?.cancel();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kRegisterOtpCooldownKey);
      } catch (_) {}
      if (!mounted) return;

      final voucher = result.welcomeVoucher;
      if (voucher != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _WelcomeVoucherDialog(voucher: voucher),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Akun berhasil dibuat. Silakan login.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/member/login');
    } catch (error) {
      if (!mounted) return;
      AppHaptics.warning();
      final message = _friendlyRegisterError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyRegisterError(Object error) {
    if (error is ApiException) {
      // Detect timeout — ApiException wrap TimeoutException dari .timeout()
      // jadi message string "TimeoutException after 0:00:10.000000:
      // Future not completed". Map ke pesan friendly khusus supaya user
      // tahu ini bukan error fatal — tinggal coba lagi.
      final msg = error.message;
      final isTimeout = msg.contains('TimeoutException') ||
          msg.contains('timeout') ||
          msg.contains('Timeout');
      if (isTimeout) {
        if (!_otpSent) {
          return 'Server lambat saat mengirim OTP. Coba lagi sebentar.';
        }
        return 'Server lambat saat mendaftar. Coba lagi sebentar.';
      }
      if (error.isNetworkError) {
        if (!_otpSent) {
          return 'Pengiriman OTP belum berhasil. Coba lagi sebentar.';
        }
        return 'Pendaftaran belum berhasil. Coba lagi sebentar.';
      }
      return error.message;
    }
    // Fallback untuk non-ApiException — generic friendly message.
    return 'Terjadi kendala. Coba lagi sebentar lagi.';
  }

  /// #3 inline validation: hitung error SEMUA field sekaligus, tampilkan
  /// inline di bawah masing-masing field (bukan toast satu-per-submit).
  /// User langsung lihat SEMUA yang salah, tidak perlu fix-submit berulang.
  bool _validate() {
    String? nameErr;
    String? emailErr;
    String? phoneErr;
    String? passwordErr;
    String? otpErr;

    if (_nameController.text.trim().isEmpty) {
      nameErr = 'Nama lengkap harus diisi.';
    }

    if (_emailController.text.trim().isEmpty) {
      emailErr = 'Email wajib diisi.';
    } else if (!_hasValidEmail) {
      emailErr = 'Format email belum sesuai.';
    }

    if (_phoneController.text.trim().isEmpty) {
      phoneErr = 'Nomor handphone wajib diisi.';
    } else if (!_hasValidPhone) {
      phoneErr = 'Nomor handphone belum sesuai.';
    }

    if (_passwordController.text.length < 8) {
      passwordErr = 'Password minimal 8 karakter.';
    }

    if (_otpSent && _otpController.text.trim().length != 6) {
      otpErr = 'Kode OTP harus 6 digit.';
    }

    setState(() {
      _nameError = nameErr;
      _emailError = emailErr;
      _phoneError = phoneErr;
      _passwordError = passwordErr;
      _otpError = otpErr;
    });

    final ok = nameErr == null &&
        emailErr == null &&
        phoneErr == null &&
        passwordErr == null &&
        otpErr == null;
    if (!ok) AppHaptics.warning();
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.pushReplacementNamed(
            context,
            '/member/login',
          ),
        ),
        title: Text(
          'Daftar Member',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          children: [
            const _RegisterHeroSection(),
            const _RegisterBenefitChips(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: cs.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.055),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: AutofillGroup(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // #2c — 2 langkah. LANGKAH 1: identitas. LANGKAH 2: OTP
                    // saja (field identitas disembunyikan supaya fokus &
                    // tidak terasa "tembok panjang"). _otpSent jadi penanda
                    // langkah aktif.
                    if (!_otpSent) ...[
                      // ── LANGKAH 1: Data diri ──
                      const _FieldLabel('Nama lengkap'),
                      _RegisterTextField(
                        controller: _nameController,
                        hint: 'Contoh: Andi Setiawan',
                        icon: Icons.person_outline_rounded,
                        autofillHints: const [AutofillHints.name],
                        errorText: _nameError,
                        onChanged: (_) {
                          if (_nameError != null) {
                            setState(() => _nameError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Email'),
                      _RegisterTextField(
                        controller: _emailController,
                        hint: 'Contoh: nama@email.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        errorText: _emailError,
                        onChanged: (_) {
                          if (_emailError != null) {
                            setState(() => _emailError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('No. handphone'),
                      _RegisterTextField(
                        controller: _phoneController,
                        hint: 'Contoh: 0812-3456-789',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        errorText: _phoneError,
                        inputFormatters: [PhoneFormatter()],
                        onChanged: (_) {
                          if (_phoneError != null) {
                            setState(() => _phoneError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      const _OtpInfoBox(),
                      const SizedBox(height: 14),
                      const _FieldLabel('Password'),
                      // #2a — konfirmasi password DIHAPUS. User pakai tombol
                      // 👁 (show/hide) untuk verifikasi sendiri ketikannya.
                      _RegisterTextField(
                        controller: _passwordController,
                        hint: 'Minimal 8 karakter',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePassword,
                        autofillHints: const [AutofillHints.newPassword],
                        errorText: _passwordError,
                        onToggleObscure: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                        onChanged: (_) {
                          if (_passwordError != null) {
                            setState(() => _passwordError = null);
                          }
                        },
                      ),
                    ] else ...[
                      // ── LANGKAH 2: Verifikasi OTP ──
                      Text(
                        'Verifikasi akun',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Masukkan kode yang kami kirim ke email & WhatsApp kamu.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Kode OTP'),
                      _RegisterTextField(
                        controller: _otpController,
                        hint: 'Masukkan 6 digit kode',
                        icon: Icons.password_rounded,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        errorText: _otpError,
                        // #6: batasi 6 digit angka + auto-submit saat lengkap
                        // (konsisten dengan login OTP).
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (value) {
                          if (_otpError != null) {
                            setState(() => _otpError = null);
                          }
                          // Auto-submit begitu 6 digit terisi (mis. autofill
                          // OTP dari SMS) + form valid + tidak sedang loading.
                          if (value.trim().length == 6 &&
                              !_loading &&
                              _canSubmit) {
                            _onPrimary();
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      // Destination hint — confirmasi ke user OTP dikirim
                      // ke mana, supaya tidak bingung buka email vs WA.
                      _OtpDestinationHint(
                        email: _emailController.text.trim(),
                        phone: _phoneController.text.trim(),
                      ),
                      const SizedBox(height: 10),
                      // Resend OTP row — disabled selama countdown 60s.
                      _ResendOtpRow(
                        countdown: _resendCountdown,
                        loading: _resendingOtp,
                        onTap: _resendOtp,
                      ),
                      const SizedBox(height: 4),
                      // Kembali ke langkah 1 untuk ubah email/HP/dll.
                      Center(
                        child: TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _otpSent = false),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Ubah data'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _RegisterSubmitButton(
                      onPressed: _canSubmit ? _onPrimary : null,
                      loading: _loading,
                      otpSent: _otpSent,
                    ),
                  ],
                ),
                ),
              ),
            ),
            const _RegisterMemberBenefitCard(),
            _BackToLoginLink(
              onTap: () =>
                  Navigator.pushReplacementNamed(context, '/member/login'),
            ),
            SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RegisterHeroSection extends StatelessWidget {
  const _RegisterHeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        // Hero gradient terang tetap di-keep (artwork), pakai literal warna
        // bekas _softBlueBg supaya tampilan hero tidak berubah.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFF1F7FF)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AspectRatio(
              aspectRatio: 853 / 385,
              child: Image.asset(
                'assets/images/register_member_hero_petshop.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const _HeroFallback(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Daftar Member Natalo',
              textAlign: TextAlign.center,
              style: TextStyle(
                // Teks di atas hero gradient terang (di-keep) tetap gelap.
                color: Color(0xFF101828),
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              'Gratis! Kumpulkan poin dan dapatkan voucher khusus member.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_brandBlue, _brandBlueDark],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(
        child: Icon(Icons.pets_rounded, color: Colors.white, size: 76),
      ),
    );
  }
}

class _RegisterBenefitChips extends StatelessWidget {
  const _RegisterBenefitChips();

  @override
  Widget build(BuildContext context) {
    const items = [
      _BenefitChipData(
        icon: Icons.pets_rounded,
        title: 'Poin Belanja',
        subtitle: 'Kumpulkan poin setiap transaksi',
      ),
      _BenefitChipData(
        icon: Icons.confirmation_number_rounded,
        title: 'Voucher Member',
        subtitle: 'Dapatkan voucher khusus member',
      ),
      _BenefitChipData(
        icon: Icons.local_offer_rounded,
        title: 'Promo Khusus',
        subtitle: 'Harga spesial untuk member',
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _BenefitChip(item: items[index]),
      ),
    );
  }
}

class _BenefitChipData {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitChipData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _BenefitChip extends StatelessWidget {
  final _BenefitChipData item;

  const _BenefitChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_brandBlue, _brandBlueDark],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

class _RegisterTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final List<TextInputFormatter>? inputFormatters;
  // #1 autofill: hint untuk Google Password Manager / auto-isi OTP.
  final List<String>? autofillHints;
  // #3 inline validation: pesan error di bawah field (null = tidak ada).
  final String? errorText;
  // #3: clear error saat user mulai memperbaiki.
  final ValueChanged<String>? onChanged;

  const _RegisterTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.onToggleObscure,
    this.inputFormatters,
    this.autofillHints,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      onChanged: onChanged,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        hintStyle: const TextStyle(
          color: Color(0xFF98A2B3),
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 22),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                tooltip:
                    obscure ? 'Tampilkan password' : 'Sembunyikan password',
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF6B7280),
                ),
              ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? cs.surfaceContainerHighest
            : const Color(0xFFF8FBFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _brandBlue, width: 1.5),
        ),
        // Error border senada style rounded (#3 inline validation).
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5484D)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5484D), width: 1.5),
        ),
      ),
    );
  }
}

class _RegisterSubmitButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final bool otpSent;

  const _RegisterSubmitButton({
    required this.onPressed,
    required this.loading,
    required this.otpSent,
  });

  @override
  State<_RegisterSubmitButton> createState() => _RegisterSubmitButtonState();
}

class _RegisterSubmitButtonState extends State<_RegisterSubmitButton> {
  final ActionThrottle _throttle = ActionThrottle(
    interval: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _RegisterSubmitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading && !widget.loading) {
      _throttle.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.loading
        ? (widget.otpSent ? 'Mendaftarkan...' : 'Mengirim OTP...')
        : (widget.otpSent ? 'Daftar' : 'Kirim OTP');

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed:
            widget.loading ? null : () => _throttle.run(widget.onPressed),
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _brandBlue.withValues(alpha: 0.38),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.86),
          elevation: widget.onPressed == null ? 0 : 8,
          shadowColor: _brandBlue.withValues(alpha: 0.28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey(label),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpInfoBox extends StatelessWidget {
  const _OtpInfoBox();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
            : _softBlueCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E8FF)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CircleIcon(icon: Icons.info_rounded, size: 38),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kode OTP dikirim ke email dan WhatsApp.',
                  style: TextStyle(
                    color: _brandBlueDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Gunakan satu kode yang sama. WhatsApp bisa membutuhkan 30-60 detik.',
                  style: TextStyle(
                    color: Color(0xFF24527A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.32,
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

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _CircleIcon({required this.icon, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _brandBlue,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.54),
    );
  }
}

class _RegisterMemberBenefitCard extends StatelessWidget {
  const _RegisterMemberBenefitCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0B7FEA).withValues(alpha: 0.20)
                  : _softBlueCard,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: _brandBlue,
              size: 42,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kenapa daftar member Natalo?',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const _BenefitBullet(
                  text: 'Kumpulkan loyalty poin setiap transaksi',
                ),
                const SizedBox(height: 7),
                const _BenefitBullet(
                  text: 'Dapat voucher dan promo khusus member',
                ),
                const SizedBox(height: 7),
                const _BenefitBullet(
                  text: 'Checkout lebih cepat dengan data akun tersimpan',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitBullet extends StatelessWidget {
  final String text;

  const _BenefitBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1, right: 8),
          child: Icon(
            Icons.check_circle_rounded,
            color: _brandBlue,
            size: 17,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _BackToLoginLink extends StatelessWidget {
  final VoidCallback onTap;

  const _BackToLoginLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Text.rich(
          TextSpan(
            text: 'Sudah punya akun? ',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            children: const [
              TextSpan(
                text: 'Masuk',
                style: TextStyle(
                  color: _brandBlueDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Destination hint — info ke user OTP dikirim ke email + WA mana.
/// Phone di-mask partial untuk privacy: 0812***4567 (4 awal + 4 akhir
/// visible, sisanya bintang). Match pattern IG/Tokopedia OTP screen.
class _OtpDestinationHint extends StatelessWidget {
  final String email;
  final String phone;

  const _OtpDestinationHint({required this.email, required this.phone});

  String _maskPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length <= 8) return digits;
    final start = digits.substring(0, 4);
    final end = digits.substring(digits.length - 4);
    return '$start${'*' * (digits.length - 8)}$end';
  }

  String _maskEmail(String raw) {
    final clean = raw.trim();
    final at = clean.indexOf('@');
    if (at <= 0) return clean;
    final local = clean.substring(0, at);
    final domain = clean.substring(at);
    if (local.length <= 2) return clean;
    final visible = local.substring(0, 2);
    return '$visible${'*' * (local.length - 2)}$domain';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          children: [
            const TextSpan(text: 'Kode dikirim ke '),
            TextSpan(
              text: _maskPhone(phone),
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const TextSpan(text: ' dan '),
            TextSpan(
              text: _maskEmail(email),
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resend OTP row — disabled selama countdown >0 ("Tunggu 45s"), enabled
/// kalau 0 ("Kirim Ulang Kode"). Tap → trigger parent _resendOtp().
/// Loading state saat request in-flight (spinner kecil).
class _ResendOtpRow extends StatelessWidget {
  final int countdown;
  final bool loading;
  final VoidCallback onTap;

  const _ResendOtpRow({
    required this.countdown,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = countdown > 0 || loading;
    final label = loading
        ? 'Mengirim ulang...'
        : countdown > 0
            ? 'Kirim ulang dalam ${countdown}s'
            : 'Kirim Ulang Kode';
    final color = disabled ? cs.onSurfaceVariant : _brandBlueDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rp1.234.567 — thousands separator titik, tanpa desimal.
String _formatRupiah(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}

/// Popup voucher selamat datang — tampil sekali setelah registrasi
/// sukses. Warna biru brand + aksen amber/coral, motif paw khas
/// petshop. Tidak auto-dismiss — user tap salah satu tombol.
class _WelcomeVoucherDialog extends StatelessWidget {
  final WelcomeVoucherInfo voucher;
  const _WelcomeVoucherDialog({required this.voucher});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          color: _brandBlue,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFAC775).withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    left: -36,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 20,
                    left: 22,
                    child: Icon(Icons.pets_rounded,
                        size: 18, color: Color(0x4DFFFFFF)),
                  ),
                  const Positioned(
                    top: 60,
                    right: 36,
                    child: Icon(Icons.pets_rounded,
                        size: 14, color: Color(0x40FFFFFF)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAC775),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Khusus member baru',
                            style: TextStyle(
                              color: Color(0xFF412402),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Selamat datang di Natalo!',
                          style: TextStyle(
                            color: Color(0xDDFFFFFF),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rp${_formatRupiah(voucher.discountAmount)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'langsung potong belanja pertamamu',
                          style: TextStyle(
                            color: Color(0xBFFFFFFF),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _VoucherInfoCell(
                        label: 'Min. belanja',
                        value: 'Rp${_formatRupiah(voucher.minimumOrder)}',
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      _VoucherInfoCell(
                        label: 'Berlaku',
                        value: '${voucher.expiresAfterDays} hari',
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 22),
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD85A30),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Pakai voucher sekarang'),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 16),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Simpan untuk nanti',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherInfoCell extends StatelessWidget {
  final String label;
  final String value;
  const _VoucherInfoCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xA6FFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

