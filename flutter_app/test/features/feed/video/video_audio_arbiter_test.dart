import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_audio_arbiter.dart';

void main() {
  test('last claim wins and tokens increase monotonically', () {
    final arbiter = VideoAudioArbiter();
    final ownerA = Object();
    final ownerB = Object();
    var lostA = 0;

    final a = arbiter.claim(owner: ownerA, onFocusLost: () => lostA++);
    final b = arbiter.claim(owner: ownerB, onFocusLost: () {});

    expect(b.token, greaterThan(a.token));
    expect(a.isCurrent, isFalse);
    expect(b.isCurrent, isTrue);
    expect(lostA, 1);
  });

  test('stale and repeated release cannot revoke a newer claim', () {
    final arbiter = VideoAudioArbiter();
    final a = arbiter.claim(owner: Object(), onFocusLost: () {});
    final b = arbiter.claim(owner: Object(), onFocusLost: () {});

    a.release();
    a.release();
    expect(b.isCurrent, isTrue);

    b.release();
    b.release();
    expect(b.isCurrent, isFalse);
  });

  test('focus loss fires once; same-owner refresh only stales old work', () {
    final arbiter = VideoAudioArbiter();
    final ownerA = Object();
    var lostA = 0;
    final a1 = arbiter.claim(owner: ownerA, onFocusLost: () => lostA++);
    final a2 = arbiter.claim(owner: ownerA, onFocusLost: () => lostA++);

    expect(a1.isCurrent, isFalse);
    expect(a2.isCurrent, isTrue);
    expect(lostA, 0);

    arbiter.claim(owner: Object(), onFocusLost: () {});
    expect(lostA, 1);
    a2.release();
    expect(lostA, 1);
  });
}
