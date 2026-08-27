import 'package:flutter/material.dart';

/// Batang sebaran bintang 5→1, seperti Shopee/Tokopedia.
///
/// Datanya SUDAH tersedia sejak lama: `ProductReviewSummary.ratingBreakdown`
/// diambil dari API dan di-parse ke model, tapi sebelum widget ini ada nilai
/// itu hanya dijumlahkan untuk mendapat total — sebarannya tidak pernah
/// dirender. Jadi ini murni menampilkan data yang sudah sampai di HP, tanpa
/// permintaan jaringan tambahan.
class RatingBreakdownBars extends StatelessWidget {
  const RatingBreakdownBars({
    super.key,
    required this.breakdown,
    this.barColor = const Color(0xFFF59E0B),
  });

  /// Peta bintang (1..5) → jumlah rating.
  final Map<int, int> breakdown;
  final Color barColor;

  /// Di bawah ambang ini sebaran lebih menyesatkan daripada informatif:
  /// produk dengan SATU ulasan menghasilkan satu batang penuh dan empat
  /// batang kosong, yang terbaca seperti data bermasalah padahal cuma belum
  /// cukup. Mayoritas katalog masih di bawah angka ini, jadi ambangnya bukan
  /// formalitas — ia yang menentukan fitur ini menolong atau merusak.
  static const int minRatings = 5;

  static int totalOf(Map<int, int>? breakdown) =>
      breakdown?.values.fold<int>(0, (sum, count) => sum + count) ?? 0;

  /// Gerbang tampil. Panggil ini di pemanggil, jangan mengandalkan widget
  /// mengembalikan SizedBox.shrink — supaya jarak antar-elemen di sekitarnya
  /// tidak ikut tercetak saat sebaran disembunyikan.
  static bool shouldShow(Map<int, int>? breakdown) =>
      totalOf(breakdown) >= minRatings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = totalOf(breakdown);
    if (total <= 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 5; star >= 1; star--)
          Padding(
            padding: EdgeInsets.only(bottom: star == 1 ? 0 : 5),
            child: _BreakdownRow(
              star: star,
              count: breakdown[star] ?? 0,
              total: total,
              barColor: barColor,
              trackColor: cs.surfaceContainerHighest,
              labelColor: cs.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.star,
    required this.count,
    required this.total,
    required this.barColor,
    required this.trackColor,
    required this.labelColor,
  });

  final int star;
  final int count;
  final int total;
  final Color barColor;
  final Color trackColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : count / total;
    final labelStyle = TextStyle(fontSize: 11, color: labelColor);

    return Semantics(
      // Batang adalah informasi VISUAL murni. Tanpa label ini screen reader
      // hanya mengumumkan deretan angka tanpa konteks bintangnya.
      label: '$star bintang, $count dari $total rating',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 8,
            child: Text('$star', style: labelStyle, textAlign: TextAlign.end),
          ),
          const SizedBox(width: 4),
          Icon(Icons.star_rounded, size: 11, color: barColor),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: trackColor,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 26,
            child: Text('$count', style: labelStyle, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
