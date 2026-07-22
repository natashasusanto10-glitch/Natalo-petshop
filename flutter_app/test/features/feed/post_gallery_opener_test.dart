import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/post_gallery_opener.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _p(String id) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO',
      'author': {'id': 'a', 'name': 'Tester', 'role': 'CUSTOMER'},
      'mediaItems': [
        {'mediaUrl': 'https://e.com/$id.jpg', 'kind': 'PHOTO'}
      ],
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with PostGalleryOpener<_Host> {
  final posts = [_p('a'), _p('b')];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: tileKeyFor('a'),
          onPressed: () => openPostGallery(
            posts: posts,
            index: 0,
            loadMore: (_) async => FeedPage(items: const []),
            authorIsOfficial: false,
            isOwner: false,
            authorPerPost: true,
            heroScope: 'test',
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('openPostGallery pushes MemberPostDetailScreen with full list',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.tap(find.text('open'));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
  });
}
