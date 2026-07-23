import 'new_post_user_tag.dart';

class FeedCreatePostDraft {
  final String? originalVideoPath;
  final String? localVideoPath;
  final String? trimmedVideoPath;
  final String? thumbnailPath;
  final Duration? originalDuration;
  final Duration? trimmedDuration;

  /// Titik mulai potong pilihan user (layar trim). Kompresi video terjadi
  /// di store (Approach B — FeedUploadStore), BUKAN di layar trim; field
  /// ini yang membawa pilihan range dari layar trim ke store.
  final Duration? trimStart;
  final int? fileSizeBytes;
  final String caption;
  final List<String> taggedProductIds;
  final List<NewPostUserTag> taggedUsers;
  final String? originalFilename;
  final String? mimeType;

  /// True bila thumbnailPath dipilih user via Ubah Sampul — store TIDAK
  /// boleh me-regenerate cover (guard di _runVideoUpload step 1).
  final bool userPickedCover;

  const FeedCreatePostDraft({
    this.originalVideoPath,
    this.localVideoPath,
    this.trimmedVideoPath,
    this.thumbnailPath,
    this.originalDuration,
    this.trimmedDuration,
    this.trimStart,
    this.fileSizeBytes,
    this.caption = '',
    this.taggedProductIds = const [],
    this.taggedUsers = const [],
    this.originalFilename,
    this.mimeType,
    this.userPickedCover = false,
  });

  String? get finalVideoPath => trimmedVideoPath ?? localVideoPath;

  Duration? get finalDuration => trimmedDuration ?? originalDuration;

  FeedCreatePostDraft copyWith({
    String? originalVideoPath,
    String? localVideoPath,
    String? trimmedVideoPath,
    String? thumbnailPath,
    Duration? originalDuration,
    Duration? trimmedDuration,
    Duration? trimStart,
    int? fileSizeBytes,
    String? caption,
    List<String>? taggedProductIds,
    List<NewPostUserTag>? taggedUsers,
    String? originalFilename,
    String? mimeType,
    bool? userPickedCover,
  }) {
    return FeedCreatePostDraft(
      originalVideoPath: originalVideoPath ?? this.originalVideoPath,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      trimmedVideoPath: trimmedVideoPath ?? this.trimmedVideoPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      originalDuration: originalDuration ?? this.originalDuration,
      trimmedDuration: trimmedDuration ?? this.trimmedDuration,
      trimStart: trimStart ?? this.trimStart,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      caption: caption ?? this.caption,
      taggedProductIds: taggedProductIds ?? this.taggedProductIds,
      taggedUsers: taggedUsers ?? this.taggedUsers,
      originalFilename: originalFilename ?? this.originalFilename,
      mimeType: mimeType ?? this.mimeType,
      userPickedCover: userPickedCover ?? this.userPickedCover,
    );
  }
}

/// Argumen kompresi dari draft — dipakai FeedUploadStore.
/// trimStart null = kompres penuh tanpa potong.
({int? startTimeSec, int? durationSec}) compressRangeOf(FeedCreatePostDraft d) {
  if (d.trimStart == null) return (startTimeSec: null, durationSec: null);
  return (
    startTimeSec: d.trimStart!.inSeconds,
    durationSec: (d.trimmedDuration ?? d.originalDuration)?.inSeconds,
  );
}
