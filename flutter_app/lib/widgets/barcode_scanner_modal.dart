import 'package:flutter/material.dart';

/// Barcode scanner — TEMPORARILY DISABLED.
///
/// File ini sebelumnya pakai `mobile_scanner: ^5.2.3` untuk barcode/QR
/// scan via ML Kit. Tapi mobile_scanner 5.x depend ke MLKit + GoogleDataTransport
/// 9.x, konflik dengan Firebase 11.x yang depend ke GoogleDataTransport 10.x.
/// Akibatnya pod install di iOS fail.
///
/// Sampai mobile_scanner naik ke versi 7.x+ (yang compat dengan
/// MLKit + GoogleDataTransport 10.x), file ini stub no-op.
///
/// Tidak ada screen di lib/screens/ yang import file ini saat ini, jadi
/// stubbing aman — barcode scanner feature tidak hilang dari user experience
/// (belum pernah di-expose). Saat re-enable, restore implementation original
/// dari git history.

/// Tampilkan barcode scanner — stub no-op, return null (user cancel).
Future<String?> showBarcodeScanner(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Belum tersedia'),
      content: const Text(
        'Barcode scanner sedang dinonaktifkan karena update dependency. '
        'Akan kembali tersedia di update berikutnya.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return null;
}
