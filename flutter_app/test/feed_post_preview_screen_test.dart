import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_anchor_card.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/screens/feed_new_post_screen.dart' show NewPostMediaDraft;
import 'package:natalo_petshop_flutter/screens/feed_post/feed_post_preview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const vd = FeedCreatePostDraft(
    localVideoPath: '/nonexistent/v.mp4',
    originalDuration: Duration(seconds: 20),
  );
  final produk = Product(
    id: 'p1', slug: 'p1', title: 'Majes Magic Bites', category: '', brand: '',
    imageUrl: '', price: 159000, discountPrice: 129000,
    rating: 0, reviewCount: 0, stock: 3, description: '',
  );

  Future<void> pumpIt(WidgetTester tester, {List<Product> products = const []}) async {
    await tester.pumpWidget(MaterialApp(home: FeedPostPreviewScreen(
      draft: const NewPostMediaDraft.video(vd),
      videoDraft: vd, caption: 'Halo dunia kucing', products: products,
    )));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
  }

  testWidgets('chrome feed asli: FeedActionRail + caption + dual tombol',
      (tester) async {
    await pumpIt(tester);
    expect(find.text('Pratinjau'), findsOneWidget);
    expect(find.byType(FeedActionRail), findsOneWidget);
    expect(find.textContaining('Halo dunia kucing'), findsOneWidget);
    expect(find.text('Simpan Draft'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
  });

  testWidgets('rail non-interaktif (IgnorePointer) + kartu produk tampil '
      'saat ada produk tertag', (tester) async {
    await pumpIt(tester, products: [produk]);
    expect(find.byType(FeedProductAnchorCard), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(FeedActionRail), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
  });

  testWidgets('Bagikan pop FeedPreviewResult.share', (tester) async {
    FeedPreviewResult? out;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return ElevatedButton(onPressed: () async {
        out = await Navigator.push<FeedPreviewResult>(context, MaterialPageRoute(
          builder: (_) => FeedPostPreviewScreen(
            draft: const NewPostMediaDraft.video(vd), videoDraft: vd,
            caption: '', products: const [])));
      }, child: const Text('go'));
    })));
    await tester.tap(find.text('go'));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    await tester.tap(find.text('Bagikan'));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(out, FeedPreviewResult.share);
  });
}
