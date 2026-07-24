/**
 * Pure helpers agregasi notifikasi follow ala IG (spec
 * docs/superpowers/specs/2026-07-24-notif-aggregation-ig-design.md).
 * Tanpa I/O supaya teruji langsung (pola tests/ repo ini: node:test tanpa DB).
 */

/** Window agregasi — SAMA dengan LIKE_BATCH_WINDOW_MS jalur like. */
export const FOLLOW_AGG_WINDOW_MS = 30 * 60 * 1000;

/** Maks 1 re-push per baris agregat per 5 menit (Keputusan 2 spec). */
export const AGG_PUSH_THROTTLE_MS = 5 * 60 * 1000;

/** Tag baris agregat follow per target — juga jadi apns-collapse-id. */
export function followAggTag(followingId: string): string {
  return `follow-agg-${followingId}`;
}

/** "{terbaru} dan {N-1} lainnya mulai mengikuti kamu" (Keputusan 4). */
export function buildFollowAggTitle(latestName: string, total: number): string {
  return `${latestName} dan ${total - 1} lainnya mulai mengikuti kamu`;
}

/**
 * Boleh re-push? Null = baris pra-migration / belum pernah → boleh
 * (kondisi eksplisit, spec Error handling). Batas 5m INKLUSIF.
 */
export function shouldRePush(lastPushedAt: Date | null, now: Date): boolean {
  if (lastPushedAt == null) return true;
  return now.getTime() - lastPushedAt.getTime() >= AGG_PUSH_THROTTLE_MS;
}
