import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../constants/official_brand.dart';

/// Regex match `@username` di text. Sama dengan server-side regex
/// `lib/feed/mentions.ts` — case-insensitive, lowercase saat ekstrak,
/// 3-30 char a-z 0-9 _ + period (no trailing dot via non-greedy
/// subdomain-style).
final RegExp _kMentionPattern = RegExp(
  r'@([a-z0-9_]+(?:\.[a-z0-9_]+)*)',
  caseSensitive: false,
);

/// MIRROR persis lib/feed/hashtags.ts (server). Boundary: '#' hanya valid
/// di awal teks atau setelah whitespace. Panjang 2-50 di-filter di kode
/// (bukan regex) — sama seperti server. Ubah di sini ⇒ ubah di sana.
final RegExp _kHashtagPattern = RegExp(
  r'(^|\s)#([a-z0-9_]+)',
  caseSensitive: false,
);
const int _kHashtagMinLength = 2;
const int _kHashtagMaxLength = 50;

/// Style hashtag: biru sama mention, w600 (mention w800) — topik lebih
/// ringan dari orang (spec §3).
const TextStyle _kDefaultHashtagStyle = TextStyle(
  color: Color(0xFF0B7FEA),
  fontWeight: FontWeight.w600,
);

/// Satu match siap-render (mention ATAU hashtag) hasil fase 1 dari
/// [buildMentionSpans] — dipakai utk sort-by-start sebelum di-render fase
/// 2. `spans` sudah lengkap (style + recognizer) supaya fase 2 tinggal
/// append apa adanya.
class _PendingSpan {
  final int start;
  final int end;
  final List<InlineSpan> spans;
  const _PendingSpan(this.start, this.end, this.spans);
}

/// Parse text dan return list InlineSpan dengan `@username` dan `#hashtag`
/// di-style sebagai tap-able link. Plain text di antara keduanya render
/// as-is.
///
/// Caller pass `onMentionTap(handle)` → callback yang fire saat user
/// tap link mention. Biasanya navigate ke /u/<handle>.
///
/// Optional `mentionStyle` — override styling (color + weight) link
/// @mention. Default: warna brand blue, bold.
/// Default plain text inherit `defaultStyle`.
///
/// Optional `onHashtagTap(name)` — callback saat user tap `#hashtag`,
/// `name` lowercase TANPA '#'. Null (default, backward-compatible) ⇒
/// hashtag tetap render sebagai teks polos, tidak tappable — dipakai di
/// layar yang belum siap navigasi hashtag. `hashtagStyle` override styling,
/// default lihat `_kDefaultHashtagStyle`.
List<InlineSpan> buildMentionSpans(
  String text, {
  required void Function(String handle) onMentionTap,
  TextStyle? defaultStyle,
  TextStyle? mentionStyle,

  /// Set of gesture recognizers — caller MUST dispose recognizers di
  /// dispose() lifecycle widget. Add ke list ini supaya caller bisa
  /// iterate clean up.
  List<TapGestureRecognizer>? collectRecognizers,

  /// Username (lowercase) yang merupakan akun admin/official. Mention ke
  /// handle ini di-brand-override: "@username" → "@Natalo Petshop" + badge
  /// verified inline. Tap tetap navigate ke profil (handle asli). Konsisten
  /// dengan FeedAuthor di feed + mention picker.
  Set<String> officialHandles = const {},
  void Function(String name)? onHashtagTap,
  TextStyle? hashtagStyle,
}) {
  if (text.isEmpty) return const [];
  final defaultMentionStyle = (defaultStyle ?? const TextStyle()).copyWith(
    color: const Color(0xFF0B7FEA),
    fontWeight: FontWeight.w800,
  );
  final effectiveMentionStyle = mentionStyle ?? defaultMentionStyle;
  final effectiveHashtagStyle = (defaultStyle ?? const TextStyle())
      .merge(hashtagStyle ?? _kDefaultHashtagStyle);

  // Fase 1: kumpulkan SEMUA match (mention + hashtag) — masing-masing
  // langsung di-build jadi span+recognizer siap pakai (builder mention di
  // bawah ini TIDAK berubah dari algoritma lama, termasuk brand-override
  // official — cuma dipindah dari loop tunggal ke sini, span-nya identik).
  // Fase 2 sort-by-start lalu render berselang-seling dgn teks polos —
  // ini yang memungkinkan mention & hashtag tercampur dalam satu teks
  // tanpa saling menimpa urutan tampil.
  final matches = <_PendingSpan>[];

  for (final match in _kMentionPattern.allMatches(text)) {
    final handle = match.group(1)!.toLowerCase();
    final recognizer = TapGestureRecognizer()
      ..onTap = () => onMentionTap(handle);
    collectRecognizers?.add(recognizer);
    if (officialHandles.contains(handle)) {
      // Brand-override: tampil "@Natalo Petshop" + badge verified inline.
      // Tap tetap pakai handle asli (navigate ke /u/<handle>).
      matches.add(_PendingSpan(match.start, match.end, [
        TextSpan(
          text: '@$kOfficialBrandName',
          style: effectiveMentionStyle,
          recognizer: recognizer,
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              Icons.verified_rounded,
              size: (effectiveMentionStyle.fontSize ?? 14) + 1,
              color: const Color(0xFF0B7FEA),
            ),
          ),
        ),
      ]));
      continue;
    }
    matches.add(_PendingSpan(match.start, match.end, [
      TextSpan(
        text: '@$handle',
        style: effectiveMentionStyle,
        recognizer: recognizer,
      ),
    ]));
  }

  if (onHashtagTap != null) {
    for (final match in _kHashtagPattern.allMatches(text)) {
      final name = match.group(2)!.toLowerCase();
      if (name.length < _kHashtagMinLength || name.length > _kHashtagMaxLength) {
        // Panjang di luar 2-50: bukan hashtag valid, biarkan jadi teks
        // polos (sama seperti server — filter di kode, bukan di regex).
        continue;
      }
      // Grup 1 ('^' zero-width ATAU satu whitespace) TIDAK ikut di-span —
      // span cuma mulai dari '#'. match.start selalu = start grup 1 (grup
      // 1 adalah token pertama di pattern), jadi posisi '#' = match.start
      // + panjang grup 1 (0 kalau '^', 1 kalau whitespace).
      final hashStart = match.start + match.group(1)!.length;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => onHashtagTap(name);
      collectRecognizers?.add(recognizer);
      matches.add(_PendingSpan(hashStart, match.end, [
        TextSpan(
          text: text.substring(hashStart, match.end),
          style: effectiveHashtagStyle,
          recognizer: recognizer,
          semanticsLabel: 'Tag $name',
        ),
      ]));
    }
  }

  matches.sort((a, b) => a.start.compareTo(b.start));

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final m in matches) {
    // Guard murni defensif: '@' dan '#' beda char jadi overlap mustahil
    // terjadi dgn pattern saat ini, tapi kalau suatu saat ada perubahan
    // regex yang membuatnya overlap, ini cegah RangeError di substring.
    if (m.start < cursor) continue;
    if (m.start > cursor) {
      spans.add(TextSpan(
        text: text.substring(cursor, m.start),
        style: defaultStyle,
      ));
    }
    spans.addAll(m.spans);
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(
      text: text.substring(cursor),
      style: defaultStyle,
    ));
  }
  return spans;
}

/// Stateful widget yang kelola recognizer lifecycle. Pakai widget ini
/// kalau lazy — gak perlu manage recognizers manually di parent.
/// Re-build saat text berubah → recognizers di-dispose + re-create.
class MentionText extends StatefulWidget {
  final String text;
  final void Function(String handle) onMentionTap;
  final TextStyle? style;
  final TextStyle? mentionStyle;
  final int? maxLines;
  final TextOverflow overflow;

  /// Handle official → brand-override render (lihat buildMentionSpans).
  final Set<String> officialHandles;

  /// Callback saat user tap `#hashtag` (lihat buildMentionSpans). Null
  /// (default) ⇒ hashtag render sebagai teks polos, tidak tappable.
  final void Function(String name)? onHashtagTap;

  /// Override styling `#hashtag` (lihat buildMentionSpans).
  final TextStyle? hashtagStyle;

  const MentionText(
    this.text, {
    super.key,
    required this.onMentionTap,
    this.style,
    this.mentionStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.officialHandles = const {},
    this.onHashtagTap,
    this.hashtagStyle,
  });

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    // Dispose dulu recognizers lama supaya tidak leak — TextSpan
    // mengikat recognizer by reference, jadi setelah rebuild span lama
    // unreachable. Fresh recognizer per build aman & deterministik.
    _disposeRecognizers();
    final spans = buildMentionSpans(
      widget.text,
      onMentionTap: widget.onMentionTap,
      defaultStyle: widget.style,
      mentionStyle: widget.mentionStyle,
      collectRecognizers: _recognizers,
      officialHandles: widget.officialHandles,
      onHashtagTap: widget.onHashtagTap,
      hashtagStyle: widget.hashtagStyle,
    );
    return Text.rich(
      TextSpan(children: spans, style: widget.style),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
