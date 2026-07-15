import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_accessibility_overlay.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('silent video indicator is informational, not a button',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: FeedNoAudioIndicator())),
      ),
    );

    expect(find.text('Tanpa suara'), findsOneWidget);
    final node =
        tester.getSemantics(find.bySemanticsLabel('Video tanpa suara'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  test('subtitle lookup follows WebVTT cue boundaries', () {
    const captions = [
      Caption(
        number: 1,
        start: Duration(seconds: 1),
        end: Duration(seconds: 3),
        text: 'Nutrisi lengkap setiap hari',
      ),
      Caption(
        number: 2,
        start: Duration(seconds: 4),
        end: Duration(seconds: 6),
        text: 'Tersedia di Natalo',
      ),
    ];

    expect(feedSubtitleTextAt(captions, const Duration(seconds: 2)),
        'Nutrisi lengkap setiap hari');
    expect(feedSubtitleTextAt(captions, const Duration(milliseconds: 3500)),
        isNull);
    expect(feedSubtitleTextAt(captions, const Duration(seconds: 5)),
        'Tersedia di Natalo');
  });
}
