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

  test('official handle @natalopetshop → "Natalo Petshop Official" + icon, tap fires real handle', () {
    String? tappedHandle;
    final spans = buildMentionSpans(
      'Halo @natalopetshop, apa kabar?',
      onMentionTap: (h) => tappedHandle = h,
      officialHandles: {'natalopetshop'},
    );

    // Assert: "@Natalo Petshop Official" brand-override text present (not raw handle)
    final textSpans = spans.whereType<TextSpan>();
    final brandSpan = textSpans.firstWhere(
      (s) => s.text == '@Natalo Petshop Official',
      orElse: () => throw 'Brand-override text "@Natalo Petshop Official" not found',
    );
    expect(brandSpan.style?.fontWeight, FontWeight.w800);
    expect(brandSpan.style?.color, const Color(0xFF0B7FEA));

    // Assert: WidgetSpan (verified icon) present in span list
    final widgetSpans = spans.whereType<WidgetSpan>();
    expect(widgetSpans.length, greaterThan(0), reason: 'No WidgetSpan found for verified icon');

    // Verify icon is verified_rounded
    final iconWidget = widgetSpans.first.child;
    expect(iconWidget, isA<Padding>());
    final iconInPadding = (iconWidget as Padding).child;
    expect(iconInPadding, isA<Icon>());
    final icon = iconInPadding as Icon;
    expect(icon.icon, Icons.verified_rounded);
    expect(icon.color, const Color(0xFF0B7FEA));

    // Assert: Tap recognizer fires with REAL underlying handle, not display text
    (brandSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(tappedHandle, 'natalopetshop',
        reason: 'Tap should fire with real handle, not display override text');
  });

  test('official handle + hashtag satu teks: keduanya render correct', () {
    String? tappedHandle;
    String? tappedTag;
    final spans = buildMentionSpans(
      'Tanya @natalopetshop tentang #grooming',
      onMentionTap: (h) => tappedHandle = h,
      onHashtagTap: (n) => tappedTag = n,
      officialHandles: {'natalopetshop'},
    );

    final textSpans = spans.whereType<TextSpan>();

    // Assert: official brand text present
    expect(
      textSpans.any((s) => s.text == '@Natalo Petshop Official'),
      isTrue,
      reason: 'Brand-override "@Natalo Petshop Official" not found',
    );

    // Assert: hashtag present and tappable
    expect(
      textSpans.any((s) => s.text == '#grooming' && s.recognizer != null),
      isTrue,
      reason: 'Hashtag "#grooming" not tappable',
    );

    // Assert: verified icon widget present
    expect(
      spans.whereType<WidgetSpan>().length,
      greaterThan(0),
      reason: 'No verified icon WidgetSpan found',
    );

    // Fire both recognizers and verify correct values
    for (final s in textSpans) {
      if (s.text == '@Natalo Petshop Official') {
        (s.recognizer as TapGestureRecognizer).onTap!();
      } else if (s.text == '#grooming') {
        (s.recognizer as TapGestureRecognizer).onTap!();
      }
    }
    expect(tappedHandle, 'natalopetshop');
    expect(tappedTag, 'grooming');
  });
}
