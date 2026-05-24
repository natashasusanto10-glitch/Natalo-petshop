import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Regex match `@username` di text. Sama dengan server-side regex
/// `lib/feed/mentions.ts` — case-insensitive, lowercase saat ekstrak,
/// 3-30 char a-z 0-9 _ + period (no trailing dot via non-greedy
/// subdomain-style).
final RegExp _kMentionPattern = RegExp(
  r'@([a-z0-9_]+(?:\.[a-z0-9_]+)*)',
  caseSensitive: false,
);

/// Parse text dan return list InlineSpan dengan `@username` di-style
/// sebagai tap-able link. Plain text di antara mention render as-is.
///
/// Caller pass `onMentionTap(handle)` → callback yang fire saat user
/// tap link. Biasanya navigate ke /u/<handle>.
///
/// Optional `mentionStyle` — override styling (color + weight) link
/// @mention. Default: warna brand blue, bold.
/// Default plain text inherit `defaultStyle`.
List<InlineSpan> buildMentionSpans(
  String text, {
  required void Function(String handle) onMentionTap,
  TextStyle? defaultStyle,
  TextStyle? mentionStyle,
  /// Set of gesture recognizers — caller MUST dispose recognizers di
  /// dispose() lifecycle widget. Add ke list ini supaya caller bisa
  /// iterate clean up.
  List<TapGestureRecognizer>? collectRecognizers,
}) {
  if (text.isEmpty) return const [];
  final defaultMentionStyle = (defaultStyle ?? const TextStyle()).copyWith(
    color: const Color(0xFF0B7FEA),
    fontWeight: FontWeight.w800,
  );
  final effectiveMentionStyle = mentionStyle ?? defaultMentionStyle;

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in _kMentionPattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(
        text: text.substring(cursor, match.start),
        style: defaultStyle,
      ));
    }
    final handle = match.group(1)!.toLowerCase();
    final recognizer = TapGestureRecognizer()
      ..onTap = () => onMentionTap(handle);
    collectRecognizers?.add(recognizer);
    spans.add(TextSpan(
      text: '@$handle',
      style: effectiveMentionStyle,
      recognizer: recognizer,
    ));
    cursor = match.end;
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

  const MentionText(
    this.text, {
    super.key,
    required this.onMentionTap,
    this.style,
    this.mentionStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
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
    );
    return Text.rich(
      TextSpan(children: spans, style: widget.style),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
