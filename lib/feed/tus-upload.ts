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

/**
 * Fingerprint resume WAJIB mengandung videoId.
 *
 * Default tus-js-client di browser adalah
 * `tus-br-<name>-<type>-<size>-<lastModified>-<endpoint>` (lihat
 * tus-js-client/lib/browser/fileSignature.js) — TIDAK memuat videoId,
 * sedangkan endpoint kita SELALU sama (video.bunnycdn.com/tusupload).
 * Jadi file yang sama selalu menghasilkan fingerprint identik, padahal
 * SETIAP percobaan upload mem-provision videoId BARU di server.
 *
 * Akibatnya satu upload gagal meninggalkan entry localStorage yang menunjuk
 * URL video LAMA. Percobaan berikutnya dengan file yang sama me-resume ke
 * URL mati itu (videonya sudah dihapus, signature juga milik guid baru),
 * PATCH chunk pertama ditolak Bunny tanpa header CORS, dan browser cuma
 * bisa melaporkan ProgressEvent "response code: n/a". Karena
 * `removeFingerprintOnSuccess` hanya menyapu saat SUKSES, entry beracun itu
 * tidak pernah hilang — file tersebut gagal diunggah SELAMANYA.
 */
export function bunnyTusFingerprint(
  videoId: string,
  file: { name?: string; size?: number; type?: string; lastModified?: number },
): string {
  return [
    "tus-bunny",
    videoId,
    file.name ?? "blob",
    file.type ?? "",
    file.size ?? 0,
    file.lastModified ?? 0,
  ].join("-");
}

/**
 * Pertahanan lapis kedua: resume HANYA kalau URL simpanan memang milik
 * videoId yang baru di-provision. Entry dari skema fingerprint lama (atau
 * storage yang dirusak tangan) tidak boleh membajak upload baru.
 */
export function shouldResumePreviousUpload(
  uploadUrl: string | null | undefined,
  videoId: string,
): boolean {
  if (!uploadUrl || !videoId) return false;
  return uploadUrl.includes(videoId);
}

/**
 * Pesan untuk kasus berkas sumber hilang dari perangkat.
 *
 * KENAPA PERLU: form Produk menunda upload sampai produk disimpan
 * ("Video akan diunggah saat produk disimpan"), jadi objek File hanya
 * menunjuk ke berkas di disk. Kalau admin memindah / mengganti nama /
 * menghapus video itu sebelum menekan Simpan, penunjuknya menggantung dan
 * browser TIDAK BISA membaca byte-nya. XHR gagal di level jaringan tanpa
 * status HTTP, sehingga tus hanya bisa melaporkan
 * "failed to upload chunk at offset 0, caused by [object ProgressEvent]"
 * — tidak ada petunjuk sama sekali bahwa penyebabnya berkas hilang.
 */
export const VIDEO_FILE_MISSING_MESSAGE =
  "File video sudah tidak bisa dibaca dari perangkat — kemungkinan sudah " +
  "dipindah, diganti nama, atau dihapus setelah dipilih. Pilih ulang videonya.";

/**
 * Baca 1 byte pertama untuk memastikan berkasnya masih ada.
 *
 * Blob hasil trim ada di memori, jadi selalu lolos. Yang disaring di sini
 * adalah File yang menunjuk ke disk — browser melempar NotFoundError saat
 * snapshot-nya sudah tidak cocok.
 */
export async function isVideoFileReadable(
  file: Pick<Blob, "slice">,
): Promise<boolean> {
  try {
    await file.slice(0, 1).arrayBuffer();
    return true;
  } catch {
    return false;
  }
}

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
      // DAN videoId yang sama, upload lanjut dari last byte.
      // Bunny TUS support resume, tapi window TTL terbatas (~24 jam).
      //
      // Fingerprint di-scope ke videoId — lihat bunnyTusFingerprint() untuk
      // alasannya (tanpa itu, satu kegagalan meracuni file selamanya).
      fingerprint: async (file) =>
        bunnyTusFingerprint(
          options.credentials.videoId,
          file as { name?: string; size?: number; type?: string; lastModified?: number },
        ),
      removeFingerprintOnSuccess: true,
      onError: (err) => {
        // Berkas bisa juga lenyap DI TENGAH upload (admin bersih-bersih
        // folder sambil menunggu). Cek ulang sebelum meneruskan error tus
        // yang tidak terbaca manusia.
        void isVideoFileReadable(options.file).then((readable) => {
          if (!readable) {
            reject(new Error(VIDEO_FILE_MISSING_MESSAGE));
            return;
          }
          reject(err instanceof Error ? err : new Error(String(err)));
        });
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
    // Gate berkas-masih-ada DULU: percuma provision & kirim chunk kalau
    // sumbernya sudah lenyap — dan pesannya jadi jelas sejak awal.
    void isVideoFileReadable(options.file).then((readable) => {
      if (!readable) {
        reject(new Error(VIDEO_FILE_MISSING_MESSAGE));
        return;
      }
      upload.findPreviousUploads().then((previousUploads) => {
        const resumable = previousUploads.find((prev) =>
          shouldResumePreviousUpload(prev.uploadUrl, options.credentials.videoId),
        );
        if (resumable) {
          upload.resumeFromPreviousUpload(resumable);
        }
        upload.start();
      }).catch(() => {
        // findPreviousUploads boleh fail kalau localStorage disabled.
        // Fallback ke fresh start.
        upload.start();
      });
    });
  });
}
