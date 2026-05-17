import 'package:flutter/services.dart';

/// Auto-format phone number Indonesia saat user mengetik di TextField.
/// - `08123456789` → `0812-3456-789`
/// - `628123456789` → `+62 812-3456-789`
/// - Handle backspace dengan benar (tidak stuck di delimiter)
///
/// Pakai:
/// ```dart
/// TextField(
///   inputFormatters: [PhoneFormatter()],
///   keyboardType: TextInputType.phone,
/// )
/// ```
class PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'[^\d+]'), '');
    if (raw.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    String formatted;
    if (raw.startsWith('+62')) {
      formatted = _formatWithPrefix(raw.substring(3), prefix: '+62 ');
    } else if (raw.startsWith('62') && raw.length > 2) {
      formatted = _formatWithPrefix(raw.substring(2), prefix: '+62 ');
    } else if (raw.startsWith('0')) {
      // Indonesia local format 08xx
      formatted = _format0Prefix(raw);
    } else {
      // Default — kelompok 4-4-4
      formatted = _formatWithPrefix(raw, prefix: '');
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _format0Prefix(String digits) {
    // Pattern: 4 (08xx) - 4 (xxxx) - 4+ (xxxx[xxx])
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 8) buf.write('-');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  String _formatWithPrefix(String digits, {required String prefix}) {
    // Pattern: prefix + 3 (xxx) - 4 (xxxx) - 4+ (xxxx[xxx])
    final buf = StringBuffer(prefix);
    for (var i = 0; i < digits.length; i++) {
      if (i == 3 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}
