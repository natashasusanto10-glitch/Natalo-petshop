import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';

void main() {
  group('postDetailShowsVideoSurface', () {
    test('draws the live surface whenever the controller is initialized — '
        'independent of playback being paused for a close/back transition', () {
      // Reverse/close pauses playback (playbackAllowed=false) before the
      // surface moves. The controller stays initialized and still holds its
      // last decoded frame, so the surface must remain the video. The
      // decision does not take playbackAllowed at all: it cannot swap to the
      // thumbnail just because playback paused. Swapping to the thumbnail
      // there was the "closing a posted video glitches" bug (the thumbnail
      // reloads shimmer/black mid-zoom).
      expect(postDetailShowsVideoSurface(controllerInitialized: true), isTrue);
    });

    test('draws the thumbnail when no controller is initialized yet', () {
      expect(
        postDetailShowsVideoSurface(controllerInitialized: false),
        isFalse,
      );
    });
  });
}
