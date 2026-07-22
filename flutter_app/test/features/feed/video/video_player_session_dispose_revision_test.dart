import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';

/// LOW dari review Hero gesture-pop gate: `_disposeOnce` men-dispose
/// controller TANPA membump `revision` — `_HeroVideoFlightSurface`
/// (member_post_detail_screen.dart) baca controller sinkron dari sesi via
/// `revision` listener, jadi kalau dispose terjadi persis selagi shuttle
/// aktif, surface bisa terus memegang controller yang sudah mati alih-alih
/// rebuild ke fallback thumbnail.
///
/// Fix: `_disposeOnce` sekarang membump `revision.value` setelah cleanup
/// resource selesai, supaya listener manapun (termasuk surface flight)
/// tahu harus rebuild.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose() membump revision supaya listener rebuild ke fallback',
      () async {
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      debugInitAttempt: (_) async {},
      debugDisposePlayer: () async {},
    );
    await pumpEventQueue();

    final before = session.revision.value;
    var notified = false;
    session.revision.addListener(() => notified = true);

    await session.dispose();

    expect(notified, isTrue,
        reason: 'listener revision (mis. _HeroVideoFlightSurface) harus dapat '
            'notifikasi saat sesi di-dispose supaya rebuild ke fallback '
            'alih-alih terus pegang controller mati');
    expect(session.revision.value, isNot(equals(before)),
        reason: 'revision harus berubah (di-bump) saat dispose');
  });
}
