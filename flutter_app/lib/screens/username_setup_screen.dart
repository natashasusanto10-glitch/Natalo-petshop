import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';

const _brandBlue = NataloColors.primary;
const _successGreen = Color(0xFF10B981);
const _dangerRed = Color(0xFFEF4444);

/// Username set/change screen — IG/TikTok-style flow.
/// Live availability check sambil user ketik (debounced 350ms).
/// Visual feedback inline: check hijau / X merah + reason.
class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  late final TextEditingController _controller;
  Timer? _debounce;
  bool _checking = false;
  bool _saving = false;
  UsernameAvailability? _result;
  String? _formatError;
  DateTime? _nextAllowedAt;

  bool get _inCooldown =>
      _nextAllowedAt != null && _nextAllowedAt!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    final current = memberStore.profile?.username ?? '';
    _controller = TextEditingController(text: current);
    _controller.addListener(_onChanged);
    memberService.fetchUsernameNextAllowedAt().then((value) {
      if (!mounted) return;
      setState(() => _nextAllowedAt = value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final raw = _controller.text.trim();
    final localError = _validateLocal(raw);
    setState(() {
      _formatError = localError;
      _result = null;
    });
    _debounce?.cancel();
    if (localError != null) return;
    if (raw == memberStore.profile?.username) {
      // Same as current — skip server check.
      setState(() => _result = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runCheck(raw);
    });
  }

  /// Validasi format CLIENT-SIDE — match rules backend (lib/username.ts).
  /// Return error message kalau invalid, null kalau OK lanjut server check.
  String? _validateLocal(String raw) {
    if (raw.isEmpty) return null; // belum mulai ketik, no error
    if (raw.length < 3) return 'Minimal 3 karakter.';
    if (raw.length > 30) return 'Maksimal 30 karakter.';
    if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(raw)) {
      return 'Hanya boleh huruf kecil, angka, _, dan titik.';
    }
    if (raw.startsWith('.')) return 'Tidak boleh diawali titik.';
    if (raw.endsWith('.')) return 'Tidak boleh diakhiri titik.';
    if (raw.contains('..')) return 'Tidak boleh dua titik berurutan.';
    return null;
  }

  Future<void> _runCheck(String raw) async {
    if (!mounted) return;
    setState(() => _checking = true);
    final result = await memberService.checkUsernameAvailable(raw);
    if (!mounted) return;
    // Race guard — kalau user udah ganti text antara, abaikan stale result.
    if (_controller.text.trim() != raw) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  bool get _canSave {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return false;
    if (_formatError != null) return false;
    if (_checking || _saving) return false;
    if (_inCooldown && raw != memberStore.profile?.username) return false;
    // Same as current → save no-op tapi user mungkin mau "konfirmasi", OK enable.
    if (raw == memberStore.profile?.username) return true;
    return _result?.available == true;
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();
    if (!_canSave) return;
    AppHaptics.tap();
    setState(() => _saving = true);
    try {
      final newUsername = await memberService.setUsername(raw);
      if (!mounted) return;
      // Optimistic sync to memberStore biar UI lain instant update.
      final current = memberStore.profile;
      final wasChanged = current?.username != newUsername;
      if (current != null) {
        memberStore.setProfile(current.copyWith(username: newUsername));
      }
      if (wasChanged) {
        setState(
          () => _nextAllowedAt = DateTime.now().add(const Duration(days: 30)),
        );
      }
      AppHaptics.success();
      AppToast.show(
        context,
        'Username @$newUsername berhasil disimpan',
        kind: ToastKind.success,
      );
      Navigator.maybePop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, e.message, kind: ToastKind.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(
        context,
        'Gagal simpan username. Coba lagi.',
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
        ),
        title: const Text(
          'Username',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'Username publik @kamu',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Username dipakai untuk @mention di komentar/caption dan '
            'URL profile kamu. Bisa diganti maksimal sekali tiap 30 hari — '
            'handle lama akan di-reserve 30 hari supaya tidak diambil '
            'orang lain.',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (_inCooldown) ...[
            const SizedBox(height: 14),
            _CooldownBanner(nextAllowedAt: _nextAllowedAt!),
          ],
          const SizedBox(height: 20),
          _UsernameField(
            controller: _controller,
            checking: _checking,
            formatError: _formatError,
            result: _result,
            isUnchanged: _controller.text.trim() ==
                (memberStore.profile?.username ?? ''),
          ),
          const SizedBox(height: 14),
          _RulesPanel(),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: _brandBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan Username'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CooldownBanner extends StatelessWidget {
  final DateTime nextAllowedAt;
  const _CooldownBanner({required this.nextAllowedAt});

  static const _months = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  @override
  Widget build(BuildContext context) {
    final d = nextAllowedAt;
    final formatted = '${d.day} ${_months[d.month - 1]} ${d.year}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.access_time_rounded,
              color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Kamu bisa ganti username lagi pada $formatted.',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsernameField extends StatelessWidget {
  final TextEditingController controller;
  final bool checking;
  final String? formatError;
  final UsernameAvailability? result;
  final bool isUnchanged;

  const _UsernameField({
    required this.controller,
    required this.checking,
    required this.formatError,
    required this.result,
    required this.isUnchanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = formatError != null ||
        (result != null && !result!.available && !isUnchanged);
    final isValidLive = !checking &&
        formatError == null &&
        controller.text.trim().isNotEmpty &&
        (result?.available == true || isUnchanged);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError
                  ? _dangerRed
                  : isValidLive
                      ? _successGreen
                      : cs.outlineVariant,
              width: hasError || isValidLive ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Text(
                '@',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(30),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
                  ],
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'username',
                    hintStyle: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w700,
                    ),
                    isCollapsed: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusIcon(cs),
            ],
          ),
        ),
        if (formatError != null) ...[
          const SizedBox(height: 8),
          _ErrorRow(text: formatError!),
        ] else if (result != null && !result!.available && !isUnchanged) ...[
          const SizedBox(height: 8),
          _ErrorRow(
            text: result!.message ?? 'Username tidak tersedia.',
          ),
        ] else if (isValidLive) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: _successGreen, size: 16),
              const SizedBox(width: 6),
              Text(
                isUnchanged ? 'Ini username kamu saat ini' : 'Tersedia',
                style: const TextStyle(
                  color: _successGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _statusIcon(ColorScheme cs) {
    if (checking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (formatError != null) {
      return const Icon(Icons.error_outline_rounded,
          color: _dangerRed, size: 22);
    }
    if (result != null) {
      if (result!.available || isUnchanged) {
        return const Icon(Icons.check_circle_rounded,
            color: _successGreen, size: 22);
      }
      return const Icon(Icons.cancel_rounded, color: _dangerRed, size: 22);
    }
    if (isUnchanged && controller.text.trim().isNotEmpty) {
      return Icon(Icons.check_circle_outline_rounded,
          color: cs.onSurfaceVariant, size: 22);
    }
    return const SizedBox(width: 22);
  }
}

class _ErrorRow extends StatelessWidget {
  final String text;
  const _ErrorRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: _dangerRed, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _dangerRed,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RulesPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aturan username',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          const _RuleLine('3–30 karakter'),
          const _RuleLine('Huruf kecil, angka, _ (underscore), atau . (titik)'),
          const _RuleLine('Tidak boleh diawali atau diakhiri titik'),
          const _RuleLine('Tidak boleh dua titik berurutan'),
          const _RuleLine('Handle lama di-reserve 30 hari setelah diganti'),
          const _RuleLine('Ganti username lagi baru bisa 30 hari kemudian'),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  final String text;
  const _RuleLine(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
