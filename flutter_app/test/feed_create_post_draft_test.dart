import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_create_post_draft.dart';
import 'package:natalo_petshop_flutter/models/new_post_user_tag.dart';

void main() {
  test('compressRangeOf: tanpa trimStart → kompres penuh', () {
    const d = FeedCreatePostDraft(
      localVideoPath: 'a.mp4',
      originalDuration: Duration(seconds: 40),
    );
    final r = compressRangeOf(d);
    expect(r.startTimeSec, isNull);
    expect(r.durationSec, isNull);
  });

  test('compressRangeOf: dengan trimStart + trimmedDuration', () {
    const d = FeedCreatePostDraft(
      localVideoPath: 'a.mp4',
      originalDuration: Duration(seconds: 76),
      trimStart: Duration(seconds: 10),
      trimmedDuration: Duration(seconds: 60),
    );
    final r = compressRangeOf(d);
    expect(r.startTimeSec, 10);
    expect(r.durationSec, 60);
  });

  test('copyWith mempertahankan trimStart', () {
    const d = FeedCreatePostDraft(
      localVideoPath: 'a.mp4',
      trimStart: Duration(seconds: 5),
    );
    expect(d.copyWith(caption: 'x').trimStart, const Duration(seconds: 5));
  });

  test('finalDuration fallback tetap: trimmedDuration ?? originalDuration', () {
    const d = FeedCreatePostDraft(
      originalDuration: Duration(seconds: 30),
      trimStart: Duration(seconds: 3),
      trimmedDuration: Duration(seconds: 20),
    );
    expect(d.finalDuration, const Duration(seconds: 20));
  });

  test('userPickedCover default false, copyWith set & pertahankan', () {
    const d = FeedCreatePostDraft(localVideoPath: 'a.mp4');
    expect(d.userPickedCover, isFalse);
    final picked = d.copyWith(userPickedCover: true);
    expect(picked.userPickedCover, isTrue);
    expect(picked.copyWith(caption: 'x').userPickedCover, isTrue);
  });

  test('copyWith membawa taggedUsers', () {
    const draft = FeedCreatePostDraft(caption: 'x');
    final tagged = draft.copyWith(taggedUsers: const [
      NewPostUserTag(userId: 'u1', username: 'budi', name: 'Budi'),
    ]);
    expect(tagged.taggedUsers, hasLength(1));
    expect(tagged.copyWith(caption: 'y').taggedUsers, hasLength(1));
  });
}
