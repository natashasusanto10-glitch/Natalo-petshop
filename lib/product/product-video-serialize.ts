/**
 * Fungsi murni untuk video produk — tanpa import env/DB/Bunny supaya
 * mudah diuji. Dipakai product API (serialisasi) + webhook (resolusi).
 */

// Duplikasi kecil dari status Bunny (lihat lib/feed/bunny.ts) supaya file
// ini tetap murni & tidak coupling ke modul feed.
const BUNNY_FINISHED = 4;
const BUNNY_ERROR = 5;

export type ProductVideoFields = {
  videoUrl: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
};

const EMPTY: ProductVideoFields = {
  videoUrl: null,
  videoThumbnailUrl: null,
  videoDurationSec: null,
};

/**
 * Kembalikan field video untuk client HANYA saat video benar-benar
 * playable (`ready` + punya URL). Selain itu semua null supaya client
 * lama aman & produk tanpa video tidak bocor URL setengah jadi.
 */
export function productVideoPayload(p: {
  videoStatus: string | null;
  videoUrl: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
}): ProductVideoFields {
  if (p.videoStatus === "ready" && p.videoUrl) {
    return {
      videoUrl: p.videoUrl,
      videoThumbnailUrl: p.videoThumbnailUrl ?? null,
      videoDurationSec: p.videoDurationSec ?? null,
    };
  }
  return { ...EMPTY };
}

export type ProductVideoWebhookUpdate =
  | { kind: "processing" }
  | {
      kind: "ready";
      videoUrl: string;
      videoThumbnailUrl: string;
      videoDurationSec: number | null;
    }
  | { kind: "failed" }
  | { kind: "ignore" };

/**
 * Petakan callback Bunny → aksi DB. `ignore` saat row sudah settled
 * (webhook retry). Non-terminal → processing. ERROR → failed.
 * FINISHED → ready dengan URL HLS + thumbnail.
 */
export function resolveProductVideoWebhookUpdate(input: {
  status: number;
  currentStatus: string | null;
  playlistUrl: string;
  thumbnailUrl: string;
  durationSec: number | null;
}): ProductVideoWebhookUpdate {
  if (input.currentStatus === "ready" || input.currentStatus === "failed") {
    return { kind: "ignore" };
  }
  if (input.status === BUNNY_ERROR) return { kind: "failed" };
  if (input.status !== BUNNY_FINISHED) return { kind: "processing" };
  return {
    kind: "ready",
    videoUrl: input.playlistUrl,
    videoThumbnailUrl: input.thumbnailUrl,
    videoDurationSec: input.durationSec,
  };
}
