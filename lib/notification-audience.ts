/**
 * Klausa pemilih notifikasi untuk /api/notifications/me.
 *
 * Dipisah ke helper murni supaya aturan terpentingnya bisa dites tanpa
 * database: BROADCAST hanya yang terbit SETELAH akun si penonton lahir.
 * Tanpa batas itu, akun yang baru mendaftar langsung disuguhi seluruh
 * tumpukan pengumuman lama sebagai "belum dibaca" — badge menyala untuk
 * hal-hal yang terjadi sebelum akunnya ada. Broadcast tanpa `endsAt`
 * hidup selamanya, jadi tumpukan itu tidak pernah menyusut sendiri.
 */
export function announcementAudienceWhere({
  userId,
  allowedSegments,
  viewerCreatedAt,
}: {
  userId: string;
  allowedSegments: string[];
  /**
   * Tanggal akun dibuat. `null` = row user tak ditemukan (sesi hidup tapi
   * akun terhapus) — jangan memfilter, kembali ke perilaku lama alih-alih
   * menyembunyikan semuanya.
   */
  viewerCreatedAt: Date | null;
}) {
  return {
    OR: [
      {
        targetUserId: null,
        segment: { in: allowedSegments },
        ...(viewerCreatedAt ? { createdAt: { gte: viewerCreatedAt } } : {}),
      },
      // Personal (status pesanan, poin, aktivitas feed) SENGAJA tanpa batas
      // tanggal — semuanya memang tercipta untuk akun ini, dan memfilternya
      // bisa menyembunyikan notifikasi yang sah.
      { targetUserId: userId },
    ],
  };
}
