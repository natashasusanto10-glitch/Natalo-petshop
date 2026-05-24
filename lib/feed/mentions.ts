/**
 * @mention parsing + lookup helpers.
 *
 * Mention text di comment/caption ditandai `@username` (sesuai format
 * validateUsernameFormat di lib/username.ts):
 *   - 3-30 char a-z 0-9 _ .
 *   - No leading/trailing `.`, no `..`
 *   - Case-insensitive (di-lowercase saat lookup ke DB).
 *
 * Karakter setelah `@` di-konsumsi sampai ketemu char non-allowed atau
 * boundary (space/newline/akhir string). Punctuation seperti `,`, `!`,
 * `?` setelah handle TIDAK termasuk handle.
 *
 * Edge case yang di-handle:
 *   - Multiple mentions di 1 text: parser dedup userId
 *   - Email-like `name@domain.com` — `@domain` regex match TAPI lookup
 *     ke DB akan return null → di-skip
 *   - Leading `.` invalid → regex tidak match
 *
 * Tidak menyimpan mention rows ke DB di Fase 3 MVP — rendering +
 * notif inline tanpa table. Kalau butuh notif feed history nanti,
 * add `Mention` model + insert disini.
 */
import { prisma } from "@/lib/prisma";

/**
 * Regex extract @username dari text. `g` flag supaya semua occurrence,
 * `i` flag supaya case-insensitive (handle lowercase di lookup phase).
 * Trailing dot di-exclude lewat lookahead biar tidak include trailing
 * punctuation (e.g. "halo @asiong." → match `asiong`, bukan `asiong.`).
 */
const MENTION_REGEX = /@([a-z0-9_]+(?:\.[a-z0-9_]+)*)/gi;

/**
 * Extract handle string mentah dari text. Return Set unique lowercased
 * handle. NO DB lookup — caller resolve via resolveMentionedUsers.
 */
export function extractMentionHandles(text: string): Set<string> {
  const handles = new Set<string>();
  if (!text) return handles;
  for (const match of text.matchAll(MENTION_REGEX)) {
    const handle = match[1].toLowerCase();
    // Minimum length matching server-side validateUsernameFormat (3 char)
    // supaya mention `@a` atau `@ab` (typo / accidental) tidak query DB.
    if (handle.length >= 3 && handle.length <= 30) {
      handles.add(handle);
    }
  }
  return handles;
}

export type MentionedUser = {
  id: string;
  username: string;
  name: string;
};

/**
 * Resolve handles → array of User (skip yg tidak exist). Dipakai di
 * comment / caption create endpoint setelah extractMentionHandles, untuk
 * kirim push notif ke user yang ke-mention.
 *
 * Skip `excludeUserId` (biasanya = actor) supaya user tidak notif diri
 * sendiri saat mention diri sendiri di komentar.
 */
export async function resolveMentionedUsers(
  handles: Set<string>,
  excludeUserId?: string,
): Promise<MentionedUser[]> {
  if (handles.size === 0) return [];
  const users = await prisma.user.findMany({
    where: {
      username: { in: [...handles] },
      ...(excludeUserId ? { id: { not: excludeUserId } } : {}),
    },
    select: { id: true, username: true, name: true },
  });
  // Filter null username (defensive — schema allow null, tapi handle list
  // hanya untuk user dengan username set).
  return users.filter(
    (u): u is MentionedUser =>
      u.username !== null && u.username.length > 0,
  ) as MentionedUser[];
}
