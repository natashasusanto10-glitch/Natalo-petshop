import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/pet.dart';
import 'package:natalo_petshop_flutter/screens/pet_care_form_screen.dart';
import 'package:natalo_petshop_flutter/widgets/care_product_picker.dart';

void main() {
  final pet = Pet(
    id: 'pet1',
    name: 'Bobby',
    type: 'Anjing',
    weightKg: 4.2,
  );

  testWidgets(
      'deworm shows weight + product picker, grooming shows place',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PetCareFormScreen(pet: pet),
    ));
    // Bounded pump loop instead of pumpAndSettle (shimmer/network never settles).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('Obat Cacing'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Berat'), findsWidgets);
    expect(find.byType(CareProductPicker), findsOneWidget);

    await tester.tap(find.text('Grooming'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Tempat grooming'), findsOneWidget);
    expect(find.byType(CareProductPicker), findsNothing);
  });

  testWidgets('placeholder catatan ikut kategori, bukan contoh grooming utk semua',
      (tester) async {
    // Surface tinggi: kolom Catatan ada di bawah field per-kategori, dan
    // ListView tidak membangun anak di luar viewport.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: PetCareFormScreen(pet: pet)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Default kategori (Grooming) → contoh grooming.
    expect(find.text('Mis. Mandi + potong kuku'), findsOneWidget);

    await tester.tap(find.text('Vaksin'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Mis. Tidak ada reaksi setelah vaksin'), findsOneWidget);
    expect(find.text('Mis. Mandi + potong kuku'), findsNothing,
        reason: 'contoh grooming tak boleh bocor ke kategori lain');

    await tester.tap(find.text('Periksa Dokter'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Mis. Hasil pemeriksaan & saran dokter'), findsOneWidget);
  });

  testWidgets('kotak foto tetap thumbnail 56px, tidak melebar full-width',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: PetCareFormScreen(pet: pet)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Regresi: di dalam ListView constraint cross-axis TIGHT, jadi tanpa
    // Align `width: 56` diabaikan & kotak jadi selebar layar (blok "foto
    // besar" yang spec minta dihapus).
    final box = tester.getSize(
      find.byIcon(Icons.add_a_photo_outlined).hitTestable(),
    );
    expect(box.width, lessThan(60),
        reason: 'ikon berada di dalam thumbnail 56px');

    final tappable = find.ancestor(
      of: find.byIcon(Icons.add_a_photo_outlined),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(tappable.first).width, 56);
    expect(tester.getSize(tappable.first).height, 56);
  });
}
