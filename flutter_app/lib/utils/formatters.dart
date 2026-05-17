/// String formatters — single source of truth untuk currency + date display
/// di seluruh app. Pattern Indonesia (Rp prefix, dot thousand separator,
/// nama bulan singkat 3 huruf).
///
/// Daripada inline `'${date.day} ${months[date.month - 1]} ...'` di setiap
/// screen, panggil helper di sini. Reduces inconsistency (mis. "Mei" vs
/// "May", "10:30" vs "10.30") dan memudahkan future i18n (tinggal swap
/// implementation, callsite tetap).

/// Format integer/double sebagai Rupiah dengan dot separator.
/// Contoh: `formatRupiah(50000)` → `'Rp 50.000'`
String formatRupiah(num value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    final positionFromEnd = rounded.length - i;
    buffer.write(rounded[i]);
    if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
      buffer.write('.');
    }
  }
  return 'Rp ${buffer.toString()}';
}

/// Nama bulan Indonesia singkat 3 huruf — Jan, Feb, Mar, ..., Des.
const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Format date sebagai `"DD MMM YYYY"` (mis. `'14 Mei 2026'`).
/// Pakai untuk: tanggal pesanan, tanggal voucher expired, member since.
String formatDate(DateTime date) {
  return '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';
}

/// Format date+time absolute pattern Indonesia.
/// Contoh: `'14 Mei 2026 pukul 10.33'`
/// Pakai untuk: detail pengumuman, timestamp invoice, log activity.
String formatDateTime(DateTime date) {
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '${formatDate(date)} pukul $hh.$mm';
}

/// Format date sebagai relative time dari sekarang (mis. `'2 jam lalu'`).
/// Bahasa Indonesia natural. Untuk feed posts, notifikasi, comments.
///
/// Threshold:
/// - < 1 menit: "Baru saja"
/// - < 1 jam: "X menit lalu"
/// - < 24 jam: "X jam lalu"
/// - < 30 hari: "X hari lalu"
/// - < 12 bulan: "X bulan lalu"
/// - else: "X tahun lalu"
String formatRelativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.isNegative) return 'Baru saja'; // future date = treat as now
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 30) return '${diff.inDays} hari lalu';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} bulan lalu';
  return '${(diff.inDays / 365).floor()} tahun lalu';
}

/// Format date sebagai `"MMM YYYY"` (mis. `'Mei 2026'`).
/// Pakai untuk: "Member sejak Mei 2026" di profile hero.
String formatMonthYear(DateTime date) {
  return '${_monthsShort[date.month - 1]} ${date.year}';
}
