import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/app_ui.dart';

/// Membungkus [child] dengan Material + Directionality seadanya supaya
/// InkWell punya induk yang sah tanpa menyeret tema aplikasi penuh.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('ikon 18px tetap 18px, tapi kotaknya jadi 44', (tester) async {
    await _pump(
      tester,
      const AppMinTapTarget(child: Icon(Icons.more_horiz_rounded, size: 18)),
    );

    // Ukuran VISUAL anak tidak boleh ikut membesar — itu inti widget ini.
    expect(tester.getSize(find.byIcon(Icons.more_horiz_rounded)),
        const Size(18, 18));
    expect(tester.getSize(find.byType(AppMinTapTarget)), const Size(44, 44));
  });

  testWidgets('tap di sudut area yang diperluas ikut terhitung', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      InkWell(
        onTap: () => taps++,
        child: const AppMinTapTarget(
          child: Icon(Icons.more_vert_rounded, size: 18),
        ),
      ),
    );

    final box = tester.getRect(find.byType(AppMinTapTarget));
    // Sudut kiri-atas kotak 44 berjarak 13px dari tepi ikon 18px — di area
    // yang SEBELUM perbaikan ini tidak menerima tap sama sekali.
    await tester.tapAt(box.topLeft + const Offset(3, 3));
    await tester.pump();

    expect(taps, 1,
        reason: 'area sentuh yang diperluas harus benar-benar bisa ditekan');
  });

  testWidgets('anak yang sudah lebih besar dari 44 tidak dikecilkan',
      (tester) async {
    await _pump(
      tester,
      const AppMinTapTarget(child: SizedBox(width: 78, height: 78)),
    );

    // 44 adalah LANTAI, bukan ukuran tetap. Thumbnail 78px harus lolos utuh.
    expect(tester.getSize(find.byType(AppMinTapTarget)), const Size(78, 78));
  });

  testWidgets('lantai bisa dinaikkan lewat size', (tester) async {
    await _pump(
      tester,
      const AppMinTapTarget(size: 48, child: Icon(Icons.star_rounded, size: 20)),
    );

    expect(tester.getSize(find.byType(AppMinTapTarget)), const Size(48, 48));
  });
}
