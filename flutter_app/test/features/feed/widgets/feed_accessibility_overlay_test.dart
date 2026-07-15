import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_accessibility_overlay.dart';
import 'package:video_player/video_player.dart';

class _BlockingSubtitleClient extends http.BaseClient {
  final StreamController<List<int>> _stream = StreamController<List<int>>();
  int requestCount = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    return http.StreamedResponse(_stream.stream, 200);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(_stream.close());
  }
}

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

  test('subtitle URL must use the same HTTPS media host', () {
    expect(
      feedSubtitleUrlMatchesMedia(
        'https://vz-natalo.b-cdn.net/captions/post.vtt',
        'https://vz-natalo.b-cdn.net/post/playlist.m3u8',
      ),
      isTrue,
    );
    expect(
      feedSubtitleUrlMatchesMedia(
        'https://tracker.example.net/post.vtt',
        'https://vz-natalo.b-cdn.net/post/playlist.m3u8',
      ),
      isFalse,
    );
    expect(
      feedSubtitleUrlMatchesMedia(
        'http://vz-natalo.b-cdn.net/post.vtt',
        'https://vz-natalo.b-cdn.net/post/playlist.m3u8',
      ),
      isFalse,
    );
    expect(
      feedSubtitleUrlMatchesMedia(
        'https://media.attacker.example/post.vtt',
        'https://media.attacker.example/post/playlist.m3u8',
      ),
      isFalse,
      reason: 'payload media host is not a trust anchor by itself',
    );
  });

  testWidgets('hiding subtitle overlay cancels its in-flight download',
      (tester) async {
    final client = _BlockingSubtitleClient();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://vz-natalo.b-cdn.net/post/video.mp4'),
    );
    addTearDown(controller.dispose);

    Widget overlay({required bool visible}) => MaterialApp(
          home: FeedWebVttSubtitleOverlay(
            controller: controller,
            subtitleUrl: 'https://vz-natalo.b-cdn.net/captions/post-id.vtt',
            trustedMediaUrl: 'https://vz-natalo.b-cdn.net/post/playlist.m3u8',
            visible: visible,
            debugClientFactory: () => client,
          ),
        );

    await tester.pumpWidget(overlay(visible: true));
    await tester.pump();
    expect(client.requestCount, 1);
    expect(client.closed, isFalse);

    await tester.pumpWidget(overlay(visible: false));
    await tester.pump();
    expect(client.closed, isTrue);
  });
}
