import 'package:flutter/services.dart';

/// Format integer ke string Rupiah dengan separator titik. 15000 → "Rp15.000".
/// Decimal tidak digunakan — semua harga di backend Int (satuan Rupiah).
String formatRupiah(num value) {
  final isNegative = value < 0;
  final str = value.abs().toInt().toString();
  final buf = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
    buf.write(str[i]);
  }
  return '${isNegative ? '-' : ''}Rp${buf.toString()}';
}

/// Format DateTime ke string Indonesia: "12 Mei 2026".
String formatTanggal(DateTime date, {bool withTime = false}) {
  const bulan = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  final tgl = '${date.day} ${bulan[date.month - 1]} ${date.year}';
  if (!withTime) return tgl;
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '$tgl • $hh:$mm';
}

/// Relative time formatter: "2 jam lalu", "3 hari lalu".
String formatRelativeTime(DateTime past) {
  final diff = DateTime.now().difference(past);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} minggu lalu';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} bulan lalu';
  return '${(diff.inDays / 365).floor()} tahun lalu';
}

/// Truncate string with ellipsis.
String truncate(String text, int max) {
  if (text.length <= max) return text;
  return '${text.substring(0, max)}…';
}

/// Format Rupiah dengan suffix singkat: 15000 → "15rb", 1500000 → "1,5jt".
/// Dipakai di badge kecil yang space-constrained.
String formatRupiahCompact(num value) {
  if (value >= 1000000) {
    final jt = value / 1000000;
    final txt = jt == jt.roundToDouble()
        ? jt.toInt().toString()
        : jt.toStringAsFixed(1).replaceAll('.', ',');
    return 'Rp${txt}jt';
  }
  if (value >= 1000) {
    return 'Rp${(value / 1000).toInt()}rb';
  }
  return formatRupiah(value);
}

/// TextInputFormatter helper — limit max length tanpa block paste.
class MaxLengthFormatter {
  static List<TextInputFormatter> only(int max) => [
        LengthLimitingTextInputFormatter(max),
      ];
}
