import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/mention_picker.dart';

/// Test regresi @mention autocomplete (fitur sudah ada, lihat
/// lib/widgets/mention_picker.dart). Cakupan: perilaku murni
/// MentionPickerController TANPA jaringan — hanya deteksi `@partial`
/// (isActive) + insertMention. Fetch suggestion (_runSearch) di-debounce
/// 200ms lewat Timer; controller di-dispose sebelum timer sempat fire
/// supaya test tetap bounded/no-network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextEditingController textController;
  late MentionPickerController controller;

  setUp(() {
    textController = TextEditingController();
    controller = MentionPickerController(textController: textController);
  });

  tearDown(() {
    controller.dispose();
    textController.dispose();
  });

  void setTextWithCursorAtEnd(String text) {
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  test('mengetik "@par" mengaktifkan mention mode', () {
    setTextWithCursorAtEnd('halo @par');
    expect(controller.isActive, isTrue);
  });

  test('teks kosong / tanpa @ tidak mengaktifkan mention mode', () {
    setTextWithCursorAtEnd('halo dunia');
    expect(controller.isActive, isFalse);
  });

  test('alamat email (a@b.com) TIDAK mengaktifkan mention mode', () {
    // '@' didahului huruf ('a') → dianggap bagian email, bukan mention —
    // guard anti-false-positive di _detectMention.
    setTextWithCursorAtEnd('hubungi a@b.com');
    expect(controller.isActive, isFalse);
  });

  test('mention query berhenti aktif setelah spasi (mention selesai)', () {
    setTextWithCursorAtEnd('halo @par ini pesan');
    expect(controller.isActive, isFalse);
  });

  test('insertMention mengganti "@par" menjadi "@username " + cursor benar',
      () {
    setTextWithCursorAtEnd('halo @par');
    expect(controller.isActive, isTrue);

    controller.insertMention(
      const MentionUser(id: '1', name: 'Parto', username: 'parto99'),
    );

    expect(textController.text, 'halo @parto99 ');
    expect(
      textController.selection.baseOffset,
      'halo @parto99 '.length,
    );
    // Setelah insert, cursor ada di spasi trailing (bukan di dalam handle)
    // → mention mode otomatis nonaktif lagi.
    expect(controller.isActive, isFalse);
  });

  test('insertMention di tengah caption hanya mengganti range mention', () {
    setTextWithCursorAtEnd('cek @na dulu ya');
    // Pindahkan cursor ke akhir "@na" (index 7) supaya simulasikan user
    // masih mengetik mention di tengah kalimat.
    textController.value = textController.value.copyWith(
      selection: const TextSelection.collapsed(offset: 7),
    );
    expect(controller.isActive, isTrue);

    controller.insertMention(
      const MentionUser(id: '2', name: 'Nata', username: 'nata_official'),
    );

    expect(textController.text, 'cek @nata_official  dulu ya');
  });

  test('insertMention tanpa mention aktif adalah no-op', () {
    setTextWithCursorAtEnd('tidak ada mention di sini');
    expect(controller.isActive, isFalse);

    controller.insertMention(
      const MentionUser(id: '3', name: 'X', username: 'x'),
    );

    expect(textController.text, 'tidak ada mention di sini');
  });
}
