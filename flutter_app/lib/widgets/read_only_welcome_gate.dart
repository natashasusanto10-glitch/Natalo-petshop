import 'package:flutter/material.dart';

import '../utils/haptics.dart';
import '../utils/read_only_mode.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Tampilkan welcome dialog "Mode review aktif" sekali, setelah first
/// frame Home screen render. Cek SharedPreferences flag — kalau user
/// sudah dismiss, silent skip.
///
/// Dialog kasih konteks ke user:
/// - Aplikasi sedang dalam tahap testing
/// - Fitur lihat produk, kategori, pesanan tetap jalan
/// - Fitur belanja sementara via web/Capacitor
/// - Tap "Mengerti" untuk dismiss (sekali doang)
class ReadOnlyWelcomeGate extends StatefulWidget {
  final Widget child;

  const ReadOnlyWelcomeGate({super.key, required this.child});

  @override
  State<ReadOnlyWelcomeGate> createState() => _ReadOnlyWelcomeGateState();
}

class _ReadOnlyWelcomeGateState extends State<ReadOnlyWelcomeGate> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowWelcome();
    });
  }

  Future<void> _maybeShowWelcome() async {
    if (_shown) return;
    if (!readOnlyMode.isReadOnly) return;
    final dismissed = await ReadOnlyMode.isWelcomeDismissed();
    if (dismissed) return;
    if (!mounted) return;
    _shown = true;
    await _showDialog();
    await ReadOnlyMode.markWelcomeDismissed();
  }

  Future<void> _showDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _brandBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.visibility_rounded,
                  color: _brandBlue,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Mode Review Aktif',
                style: TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aplikasi Natalo Petshop versi Flutter sedang dalam tahap testing. Selama mode ini:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              const _Bullet(
                ok: true,
                text: 'Lihat produk, kategori, brand, banner asli',
              ),
              const _Bullet(
                ok: true,
                text: 'Cek pesanan, profil, voucher kamu',
              ),
              const _Bullet(
                ok: true,
                text: 'Voice search, barcode scan, biometric login',
              ),
              const _Bullet(
                ok: false,
                text: 'Checkout & belanja sementara via web/app lama',
              ),
              const _Bullet(
                ok: false,
                text: 'Tambah/edit alamat, submit review',
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  AppHaptics.tap();
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Bullet extends StatelessWidget {
  final bool ok;
  final String text;

  const _Bullet({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: ok ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ok
                    ? const Color(0xFF111111)
                    : const Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
