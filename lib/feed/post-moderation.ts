import type { FeedPostKind, FeedPostStatus } from "@prisma/client";

/**
 * Aturan status awal sebuah feed post saat dibuat (moderasi).
 *
 * Sumber kebenaran tunggal untuk keputusan "perlu review admin atau tidak":
 * - Admin  → semua kind langsung `ACTIVE` (auto-publish).
 * - Customer `PHOTO_CAROUSEL` → `ACTIVE` (auto-approve). Foto/carousel tak
 *   lagi pra-review; moderasi jadi reaktif (admin bisa Hide setelah tayang).
 * - Customer video (`COMMUNITY`) → `PENDING_REVIEW` (butuh review admin +
 *   encoding-ready sebelum tampil publik).
 *
 * Catatan: ini HANYA menentukan `status`/`publishedAt` awal. Gate visibilitas
 * publik (`PUBLIC_FEED_POST_WHERE`) tetap mensyaratkan `status: "ACTIVE"` DAN
 * `encodingStatus: "ready"`, jadi video yang di-approve tetap harus selesai
 * encoding sebelum tampil — tak tersentuh oleh helper ini.
 */
export function resolveInitialPostStatus(input: {
  isAdmin: boolean;
  kind: FeedPostKind;
}): { status: FeedPostStatus; publishedAt: Date | null } {
  const autoApprove = input.isAdmin || input.kind === "PHOTO_CAROUSEL";
  return {
    status: autoApprove ? "ACTIVE" : "PENDING_REVIEW",
    publishedAt: autoApprove ? new Date() : null,
  };
}
