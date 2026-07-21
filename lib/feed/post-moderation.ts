import type { FeedPostKind, FeedPostStatus } from "@prisma/client";

/**
 * Aturan status awal sebuah feed post saat dibuat (moderasi).
 *
 * Kebijakan sekarang: SEMUA konten (admin & customer, foto & video) langsung
 * `ACTIVE` (auto-approve, tanpa pra-review admin). Moderasi jadi reaktif —
 * admin bisa Hide/hapus setelah tayang lewat dashboard Moderasi Laporan +
 * user report sebagai jaring pengaman.
 *
 * Catatan: ini HANYA menentukan `status`/`publishedAt` awal. Gate visibilitas
 * publik (`PUBLIC_FEED_POST_WHERE`) tetap mensyaratkan `status: "ACTIVE"` DAN
 * `encodingStatus: "ready"`, jadi video tetap harus selesai encoding sebelum
 * tampil — tak tersentuh oleh helper ini (video ACTIVE + masih `uploading`
 * belum muncul di feed sampai webhook Bunny set `ready`).
 *
 * `input.kind` sengaja dipertahankan di signature meski tak lagi dipakai —
 * call site (create + upload-url) sudah kirim kind, dan kalau kebijakan
 * berubah lagi (mis. video re-review) diskriminatornya sudah tersedia.
 */
export function resolveInitialPostStatus(_input: {
  isAdmin: boolean;
  kind: FeedPostKind;
}): { status: FeedPostStatus; publishedAt: Date | null } {
  return {
    status: "ACTIVE",
    publishedAt: new Date(),
  };
}

/**
 * Apakah edit oleh customer harus mengembalikan post ke antrian review admin?
 *
 * Konsisten dengan `resolveInitialPostStatus`: sekarang TIDAK ada konten yang
 * pra-review, jadi edit (caption/tag) TIDAK pernah men-trigger review ulang —
 * foto maupun video tetap tayang. Moderasi tetap reaktif via report/Hide.
 * Selalu return false.
 */
export function editReTriggersModeration(_input: {
  isAdmin: boolean;
  status: FeedPostStatus;
  kind: FeedPostKind;
}): boolean {
  return false;
}
