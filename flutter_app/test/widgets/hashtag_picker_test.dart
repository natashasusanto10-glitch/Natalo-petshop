import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';
import 'package:natalo_petshop_flutter/utils/mention_text.dart';
import 'package:natalo_petshop_flutter/widgets/hashtag_picker.dart';

void main() {
  // Diperlukan supaya HapticFeedback.selectionClick() (dipanggil dari
  // insertHashtag) tidak throw "binding not initialized" — pola SAMA dengan
  // test/mention_picker_test.dart yang punya alasan identik (insertMention
  // juga panggil HapticFeedback.selectionClick()).
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<HashtagSuggestion>> fakeSearch(String q) async =>
      [const HashtagSuggestion(name: 'kucing', postCount: 24)];

  test('trigger # + huruf → aktif; boundary harga#promo → TIDAK aktif',
      () async {
    final text = TextEditingController();
    final ctrl =
        HashtagPickerController(textController: text, searchFn: fakeSearch);
    text.value = const TextEditingValue(
      text: 'halo #ku',
      selection: TextSelection.collapsed(offset: 8),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(ctrl.isActive, isTrue);
    expect(ctrl.suggestions.single.name, 'kucing');

    text.value = const TextEditingValue(
      text: 'harga#pro',
      selection: TextSelection.collapsed(offset: 9),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(ctrl.isActive, isFalse);
    ctrl.dispose();
    text.dispose();
  });

  test('insertHashtag: ganti #partial jadi #nama + spasi, kursor di akhir',
      () async {
    final text = TextEditingController();
    final ctrl =
        HashtagPickerController(textController: text, searchFn: fakeSearch);
    text.value = const TextEditingValue(
      text: 'halo #ku',
      selection: TextSelection.collapsed(offset: 8),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    ctrl.insertHashtag(const HashtagSuggestion(name: 'kucing', postCount: 24));
    expect(text.text, 'halo #kucing ');
    expect(text.selection.baseOffset, 'halo #kucing '.length);
    ctrl.dispose();
    text.dispose();
  });

  test('extractHashtagsFromText: mirror server (dedup, boundary, 2-50)', () {
    expect(extractHashtagsFromText('#Kucing #kucing #a harga#promo #ab_2'),
        ['kucing', 'ab_2']);
  });
}
