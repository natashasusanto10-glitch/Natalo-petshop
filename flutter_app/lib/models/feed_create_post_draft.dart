class FeedCreatePostDraft {
  final String? originalVideoPath;
  final String? localVideoPath;
  final String? trimmedVideoPath;
  final String? thumbnailPath;
  final Duration? originalDuration;
  final Duration? trimmedDuration;
  final int? fileSizeBytes;
  final String caption;
  final List<String> taggedProductIds;
  final String? originalFilename;
  final String? mimeType;

  const FeedCreatePostDraft({
    this.originalVideoPath,
    this.localVideoPath,
    this.trimmedVideoPath,
    this.thumbnailPath,
    this.originalDuration,
    this.trimmedDuration,
    this.fileSizeBytes,
    this.caption = '',
    this.taggedProductIds = const [],
    this.originalFilename,
    this.mimeType,
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
    int? fileSizeBytes,
    String? caption,
    List<String>? taggedProductIds,
    String? originalFilename,
    String? mimeType,
  }) {
    return FeedCreatePostDraft(
      originalVideoPath: originalVideoPath ?? this.originalVideoPath,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      trimmedVideoPath: trimmedVideoPath ?? this.trimmedVideoPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      originalDuration: originalDuration ?? this.originalDuration,
      trimmedDuration: trimmedDuration ?? this.trimmedDuration,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      caption: caption ?? this.caption,
      taggedProductIds: taggedProductIds ?? this.taggedProductIds,
      originalFilename: originalFilename ?? this.originalFilename,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}
