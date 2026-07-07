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

/// Alias `formatTanggal` dengan withTime=true. Beberapa code pakai
/// `formatDateTime(date)` untuk full tanggal+jam.
String formatDateTime(DateTime date) => formatTanggal(date, withTime: true);

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

/// Hitung mundur "HH:MM:SS" dari sebuah Duration. Negatif → "00:00:00".
/// Dipakai untuk item yang mepet kedaluwarsa (mis. voucher < 24 jam).
String formatCountdownHms(Duration duration) {
  if (duration.isNegative) return '00:00:00';
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
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

/// Format jumlah (follower, like, dsb) ala Instagram Indonesia:
/// 281 → "281", 1234 → "1.234", 17000 → "17 rb", 1250000 → "1,3 jt".
/// Di bawah 10rb tampil angka penuh (grouping titik) supaya presisi;
/// mulai 10rb baru diringkas jadi "rb"/"jt".
String formatCountCompact(int value) {
  if (value < 10000) return _groupThousands(value < 0 ? 0 : value);
  if (value < 1000000) {
    final rb = value / 1000;
    final txt = rb == rb.roundToDouble()
        ? rb.toInt().toString()
        : rb.toStringAsFixed(1).replaceAll('.', ',');
    return '$txt rb';
  }
  final jt = value / 1000000;
  final txt = jt == jt.roundToDouble()
      ? jt.toInt().toString()
      : jt.toStringAsFixed(1).replaceAll('.', ',');
  return '$txt jt';
}

/// Grouping ribuan dengan titik: 1234 → "1.234". Tanpa prefix "Rp".
String _groupThousands(int value) {
  final str = value.toString();
  final buf = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
    buf.write(str[i]);
  }
  return buf.toString();
}

/// TextInputFormatter helper — limit max length tanpa block paste.
class MaxLengthFormatter {
  static List<TextInputFormatter> only(int max) => [
        LengthLimitingTextInputFormatter(max),
      ];
}
