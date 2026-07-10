import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/feed_media_picker_screen.dart'
    show debugSelectedThumbStrip; // seam: expose _SelectedThumbStrip utk test

void main() {
  final items = <({String id, String path})>[
    (id: 'a', path: '/nonexistent/a.jpg'),
    (id: 'b', path: '/nonexistent/b.jpg'),
    (id: 'c', path: '/nonexistent/c.jpg'),
  ];

  testWidgets('render N thumbnail; tap memicu onTap(id) tanpa deselect',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: debugSelectedThumbStrip(items: items, activeId: 'b',
            onTap: (id) => tapped = id),
      ),
    ));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(find.byKey(const ValueKey('thumb-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('thumb-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('thumb-c')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thumb-c')));
    expect(tapped, 'c');
  });

  testWidgets('thumbnail aktif diberi border biru', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: debugSelectedThumbStrip(items: items, activeId: 'b', onTap: (_) {}),
      ),
    ));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    final active = tester.widget<Container>(find.descendant(
      of: find.byKey(const ValueKey('thumb-b')),
      matching: find.byType(Container),
    ).first);
    final deco = active.decoration as BoxDecoration;
    expect(deco.border, isNotNull);
    final activeBorder = deco.border as Border;
    expect(activeBorder.top.color, const Color(0xFF1E5BFF));

    // Bandingkan dengan tile TIDAK aktif — pastikan bukan false positive
    // (semua tile punya `border` non-null, cuma yang aktif berwarna biru).
    final inactive = tester.widget<Container>(find.descendant(
      of: find.byKey(const ValueKey('thumb-a')),
      matching: find.byType(Container),
    ).first);
    final inactiveDeco = inactive.decoration as BoxDecoration;
    final inactiveBorder = inactiveDeco.border as Border;
    expect(inactiveBorder.top.color, isNot(const Color(0xFF1E5BFF)));
  });
}
