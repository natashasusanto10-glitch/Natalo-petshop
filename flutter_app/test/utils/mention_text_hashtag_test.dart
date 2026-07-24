import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/mention_text.dart';

List<InlineSpan> spansOf(
  String text, {
  void Function(String)? onHashtagTap,
}) =>
    buildMentionSpans(
      text,
      onMentionTap: (_) {},
      onHashtagTap: onHashtagTap,
    );

String? hashtagOf(InlineSpan s) =>
    (s is TextSpan && s.text != null && s.text!.startsWith('#'))
        ? s.text
        : null;

void main() {
  test('hashtag jadi span tersendiri, biru w600, tap kirim lowercase', () {
    String? tapped;
    final spans = spansOf('Halo #KucingLucu!', onHashtagTap: (n) => tapped = n);
    final tagSpan = spans
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == '#KucingLucu');
    expect(tagSpan.style!.color, const Color(0xFF0B7FEA));
    expect(tagSpan.style!.fontWeight, FontWeight.w600);
    (tagSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(tapped, 'kucinglucu');
  });

  test('boundary mirror server: mid-word & URL fragment TIDAK tappable', () {
    for (final text in ['harga#promo', 'cek natalo.com/#promo']) {
      final spans = spansOf(text, onHashtagTap: (_) {});
      expect(spans.whereType<TextSpan>().any((s) => hashtagOf(s) != null),
          isFalse, reason: text);
    }
  });

  test('panjang mirror server: #a plain, #ab tappable', () {
    final spans = spansOf('#a #ab', onHashtagTap: (_) {});
    final tags = spans
        .whereType<TextSpan>()
        .where((s) => s.recognizer != null && s.text!.startsWith('#'))
        .map((s) => s.text)
        .toList();
    expect(tags, ['#ab']);
  });

  test('mention + hashtag satu teks: keduanya utuh', () {
    String? mention;
    String? tag;
    final spans = buildMentionSpans(
      'Sama @budi_petshop di #grooming',
      onMentionTap: (h) => mention = h,
      onHashtagTap: (n) => tag = n,
    );
    final all = spans.whereType<TextSpan>().map((s) => s.text).join();
    expect(all, 'Sama @budi_petshop di #grooming');
    expect(spans.whereType<TextSpan>().where((s) => s.recognizer != null).length, 2);
    // fire keduanya utk memastikan routing benar
    for (final s in spans.whereType<TextSpan>()) {
      (s.recognizer as TapGestureRecognizer?)?.onTap?.call();
    }
    expect(mention, 'budi_petshop');
    expect(tag, 'grooming');
  });

  test('onHashtagTap null → hashtag tetap teks polos (tanpa recognizer)', () {
    final spans = spansOf('#kucing');
    expect(
      spans.whereType<TextSpan>().any(
          (s) => s.text == '#kucing' && s.recognizer != null),
      isFalse,
    );
  });
}
