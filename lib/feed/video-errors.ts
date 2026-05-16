export class VideoTooShortError extends Error {
  constructor(minDuration: number) {
    super(`Video terlalu pendek. Minimal ${minDuration} detik.`);
    this.name = "VideoTooShortError";
  }
}

export class VideoTooLongError extends Error {
  constructor(maxDuration: number) {
    super(`Video terlalu panjang. Maksimal ${maxDuration} detik.`);
    this.name = "VideoTooLongError";
  }
}

export class VideoTooLargeError extends Error {
  constructor(maxSizeLabel: string) {
    super(
      `Ukuran video terlalu besar. Maksimal ${maxSizeLabel} — coba pilih video lebih pendek atau rekam dengan kualitas 1080p.`,
    );
    this.name = "VideoTooLargeError";
  }
}

export class CompressionFailedError extends Error {
  constructor(reason?: string) {
    super(`Gagal memproses video. ${reason || "Coba video lain."}`);
    this.name = "CompressionFailedError";
  }
}

export class FFmpegNotSupportedError extends Error {
  constructor() {
    super("Browser tidak mendukung pemrosesan video.");
    this.name = "FFmpegNotSupportedError";
  }
}
