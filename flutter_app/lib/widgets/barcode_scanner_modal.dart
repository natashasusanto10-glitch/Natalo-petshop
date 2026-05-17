import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/haptics.dart';

const _brandBlue = Color(0xFF0B7FEA);

/// Tampilkan barcode scanner full-screen. Resolves dengan barcode value
/// (string) saat scan sukses, atau `null` kalau user cancel.
///
/// Pakai mobile_scanner (ML Kit barcode) — auto-detect format apapun
/// (EAN-13, UPC, QR, Code128, dll). Native CameraX di Android +
/// AVFoundation di iOS. Throttle 1500ms supaya tidak fire ratusan kali
/// per detik dari frame berturut-turut.
Future<String?> showBarcodeScanner(BuildContext context) async {
  AppHaptics.tap();
  return Navigator.of(context).push<String>(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: const _BarcodeScannerScreen(),
      ),
    ),
  );
}

class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen>
    with TickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _scanLineController;
  bool _detected = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.qrCode,
        BarcodeFormat.itf,
      ],
    );
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    setState(() => _detected = true);
    AppHaptics.success();
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) Navigator.of(context).pop(code);
    });
  }

  Future<void> _toggleTorch() async {
    AppHaptics.tap();
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography_outlined,
                        color: Colors.white70,
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tidak bisa akses kamera',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.errorDetails?.message ??
                            'Izinkan akses kamera di pengaturan HP',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Dimmed overlay with cutout — pakai CustomPaint untuk
          // create transparent square di tengah dengan dim around it.
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ScanOverlayPainter(),
            ),
          ),

          // Animated scan line
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: 250,
              height: 250,
              child: AnimatedBuilder(
                animation: _scanLineController,
                builder: (_, __) {
                  return Stack(
                    children: [
                      Positioned(
                        left: 14,
                        right: 14,
                        top: 12 + (250 - 24) * _scanLineController.value,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _brandBlue.withValues(alpha: 0),
                                _brandBlue,
                                _brandBlue.withValues(alpha: 0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _brandBlue.withValues(alpha: 0.6),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _RoundIconButton(
                      icon: _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onPressed: _toggleTorch,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom helper text
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _detected
                                ? Icons.check_circle_rounded
                                : Icons.qr_code_scanner_rounded,
                            color: _detected
                                ? const Color(0xFF4ADE80)
                                : Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _detected
                                ? 'Barcode terdeteksi!'
                                : 'Arahkan kamera ke barcode produk',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _RoundIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // Cutout square di tengah — 250x250 dengan rounded corner.
    const boxSize = 250.0;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2;
    final rect = Rect.fromLTWH(left, top, boxSize, boxSize);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    // Draw dim using even-odd path — overlay minus cutout.
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Corner brackets di 4 sudut cutout box.
    final cornerPaint = Paint()
      ..color = _brandBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const cornerLen = 28.0;

    // Top-left
    canvas.drawLine(
        Offset(left, top + cornerLen), Offset(left, top), cornerPaint);
    canvas.drawLine(
        Offset(left, top), Offset(left + cornerLen, top), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(left + boxSize - cornerLen, top),
        Offset(left + boxSize, top), cornerPaint);
    canvas.drawLine(Offset(left + boxSize, top),
        Offset(left + boxSize, top + cornerLen), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(left, top + boxSize - cornerLen),
        Offset(left, top + boxSize), cornerPaint);
    canvas.drawLine(Offset(left, top + boxSize),
        Offset(left + cornerLen, top + boxSize), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(left + boxSize - cornerLen, top + boxSize),
        Offset(left + boxSize, top + boxSize), cornerPaint);
    canvas.drawLine(Offset(left + boxSize, top + boxSize),
        Offset(left + boxSize, top + boxSize - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
