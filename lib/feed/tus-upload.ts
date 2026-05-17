"use client";

/**
 * Client-side TUS upload wrapper untuk Bunny Stream.
 *
 * Pakai tus-js-client (~5KB gzipped) — implementasi standar TUS protocol.
 * Benefit utama vs simple XHR PUT:
 *   - Resume otomatis kalau koneksi putus (chunk-by-chunk, server tahu
 *     berapa byte sudah diterima → resume dari sana)
 *   - Background tolerant: app sleep / network switch → upload pause,
 *     resume saat conditions OK
 *   - Progress reliable per-chunk, bukan per-PUT
 *
 * Bunny TUS endpoint: https://video.bunnycdn.com/tusupload
 *
 * Header yang dikirim TUS client otomatis pakai metadata dari options.
 * Server butuh: AuthorizationSignature, AuthorizationExpire, VideoId,
 * LibraryId. Plus standard TUS headers (Tus-Resumable, Upload-Length).
 */

import * as tus from "tus-js-client";

export type BunnyTusCredentials = {
  endpoint: string;
  videoId: string;
  libraryId: string;
  authSignature: string;
  authExpire: number;
};

export type TusUploadOptions = {
  file: File | Blob;
  credentials: BunnyTusCredentials;
  /** Filetype metadata yang dikirim ke Bunny (mis. "video/mp4"). Optional. */
  filetype?: string;
  /** Title yang muncul di Bunny dashboard. Untuk korelasi manual oleh admin. */
  title?: string;
  /** Chunk size dalam byte. Default 5 MB — sweet spot resume granularity
   *  vs overhead. Lebih kecil = resume lebih akurat tapi lebih banyak
   *  HTTP request. */
  chunkSize?: number;
  /** Callback progress 0-100. */
  onProgress?: (percent: number, loaded: number, total: number) => void;
  /** Callback saat satu chunk berhasil — useful untuk save state. */
  onChunkComplete?: (chunkSize: number, bytesAccepted: number, bytesTotal: number) => void;
  /** Abort signal — dipanggil saat user cancel upload. */
  signal?: AbortSignal;
};

export type TusUploadResult = {
  url: string; // tus upload URL (untuk resume kalau perlu)
};

const DEFAULT_CHUNK_SIZE = 5 * 1024 * 1024; // 5 MB

export function uploadToBunnyViaTus(
  options: TusUploadOptions,
): Promise<TusUploadResult> {
  return new Promise((resolve, reject) => {
    const upload = new tus.Upload(options.file, {
      endpoint: options.credentials.endpoint,
      retryDelays: [0, 1000, 3000, 5000, 10000, 20000, 30000], // exponential
      chunkSize: options.chunkSize ?? DEFAULT_CHUNK_SIZE,
      headers: {
        AuthorizationSignature: options.credentials.authSignature,
        AuthorizationExpire: String(options.credentials.authExpire),
        VideoId: options.credentials.videoId,
        LibraryId: options.credentials.libraryId,
      },
      metadata: {
        filetype: options.filetype ?? "video/mp4",
        // Bunny pakai metadata.title untuk display di dashboard.
        title: options.title ?? "feed-video",
      },
      // Resume support: tus-js-client simpan upload URL di localStorage
      // by default. Kalau user buka ulang halaman dengan file yang sama
      // (file fingerprint match), upload lanjut dari last byte.
      // Bunny TUS support resume, tapi window TTL terbatas (~24 jam).
      removeFingerprintOnSuccess: true,
      onError: (err) => {
        reject(err instanceof Error ? err : new Error(String(err)));
      },
      onProgress: (bytesAccepted, bytesTotal) => {
        const percent = bytesTotal > 0
          ? Math.round((bytesAccepted / bytesTotal) * 100)
          : 0;
        options.onProgress?.(percent, bytesAccepted, bytesTotal);
      },
      onChunkComplete: (chunkSize, bytesAccepted, bytesTotal) => {
        options.onChunkComplete?.(chunkSize, bytesAccepted, bytesTotal);
      },
      onSuccess: () => {
        resolve({ url: upload.url ?? "" });
      },
    });

    // Cancel handler via AbortSignal — tus.Upload tidak punya built-in
    // abort, jadi kita panggil abort() manual saat signal fires.
    if (options.signal) {
      const onAbort = () => {
        upload.abort();
        reject(new DOMException("Upload aborted", "AbortError"));
      };
      if (options.signal.aborted) {
        onAbort();
        return;
      }
      options.signal.addEventListener("abort", onAbort, { once: true });
    }

    // Check apakah upload sebelumnya pernah ada (browser localStorage
    // fingerprint match). Kalau ya, resume dari titik itu — kalau gagal
    // cari, mulai dari 0. tus-js-client handle ini automatic.
    upload.findPreviousUploads().then((previousUploads) => {
      if (previousUploads.length > 0) {
        upload.resumeFromPreviousUpload(previousUploads[0]);
      }
      upload.start();
    }).catch(() => {
      // findPreviousUploads boleh fail kalau localStorage disabled.
      // Fallback ke fresh start.
      upload.start();
    });
  });
}
