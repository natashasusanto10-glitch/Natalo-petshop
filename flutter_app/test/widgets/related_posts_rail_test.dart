import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/related_posts_rail.dart';

Widget _harness(RelatedPostsRail rail, List<String> ids) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 190,
        child: ListView.builder(
          controller: rail.scroll,
          scrollDirection: Axis.horizontal,
          itemCount: ids.length,
          itemBuilder: (context, i) => SizedBox(
            key: rail.keyFor(ids[i]),
            width: 118,
            child: ColoredBox(color: Colors.black, child: Text(ids[i])),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('keyFor mengembalikan key yang sama untuk id yang sama', () {
    final rail = RelatedPostsRail();
    expect(identical(rail.keyFor('a'), rail.keyFor('a')), isTrue);
    expect(identical(rail.keyFor('a'), rail.keyFor('b')), isFalse);
    rail.dispose();
  });

  testWidgets('resolveReturnTarget mengukur rect kartu yang terlihat',
      (tester) async {
    final rail = RelatedPostsRail();
    final ids = List.generate(20, (i) => 'id-$i');
    await tester.pumpWidget(_harness(rail, ids));
    await tester.pumpAndSettle();

    final target = await rail.resolveReturnTarget('id-0', imageUrl: 'x');
    await tester.pumpAndSettle();

    expect(target, isNotNull);
    expect(target!.imageUrl, 'x');
    expect(target.borderRadius, 14);
    expect(target.rect.width, closeTo(118, 1));
    rail.dispose();
  });

  testWidgets('resolveReturnTarget men-scroll kartu jauh agar terlihat',
      (tester) async {
    final rail = RelatedPostsRail();
    final ids = List.generate(20, (i) => 'id-$i');
    await tester.pumpWidget(_harness(rail, ids));
    await tester.pumpAndSettle();
    expect(rail.scroll.offset, 0);

    final target = await rail.resolveReturnTarget('id-18', imageUrl: 'x');
    await tester.pumpAndSettle();

    expect(rail.scroll.offset, greaterThan(0));
    expect(target, isNotNull);
    rail.dispose();
  });

  testWidgets('resolveReturnTarget mengembalikan null untuk id tak dikenal',
      (tester) async {
    final rail = RelatedPostsRail();
    await tester.pumpWidget(_harness(rail, ['id-0']));
    await tester.pumpAndSettle();

    final target = await rail.resolveReturnTarget('hantu', imageUrl: 'x');
    expect(target, isNull);
    rail.dispose();
  });
}
