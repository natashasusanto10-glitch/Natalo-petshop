/**
 * Tag People (Spec B) — validasi input + serialisasi FeedTaggedUser.
 * Pure functions (no Prisma) supaya bisa di-unit-test via node:test.
 * Dipakai POST /api/feed/posts, POST /api/feed/bunny/upload-url, dan
 * semua serializer post yang membawa taggedUsers[].
 */
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";

export const MAX_TAGGED_USERS_PER_POST = 20;

export type TaggedUserInput = {
  userId: string;
  mediaIndex: number | null;
  x: number | null;
  y: number | null;
};

export type ParseTaggedUsersResult =
  | { ok: true; tags: TaggedUserInput[] }
  | { ok: false; error: string };

function isFraction(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1;
}

export function parseTaggedUsersInput(
  raw: unknown,
  opts: { mediaCount: number; isVideo: boolean },
): ParseTaggedUsersResult {
  if (raw === undefined || raw === null) return { ok: true, tags: [] };
  if (!Array.isArray(raw)) {
    return { ok: false, error: "taggedUsers harus berupa array." };
  }
  if (raw.length > MAX_TAGGED_USERS_PER_POST) {
    return {
      ok: false,
      error: `Maksimal ${MAX_TAGGED_USERS_PER_POST} orang yang bisa ditandai per postingan.`,
    };
  }
  const seen = new Set<string>();
  const tags: TaggedUserInput[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) {
      return { ok: false, error: "Entri taggedUsers tidak valid." };
    }
    const entry = item as Record<string, unknown>;
    const userId = String(entry.userId ?? "").trim();
    if (!userId) return { ok: false, error: "userId tag wajib diisi." };
    if (seen.has(userId)) continue; // dedupe — tag pertama menang
    seen.add(userId);

    if (opts.isVideo) {
      // Video: daftar nama saja — koordinat & media diabaikan.
      tags.push({ userId, mediaIndex: null, x: null, y: null });
      continue;
    }

    const rawIndex = entry.mediaIndex;
    const mediaIndex =
      typeof rawIndex === "number" && Number.isInteger(rawIndex) ? rawIndex : NaN;
    if (!Number.isInteger(mediaIndex) || mediaIndex < 0 || mediaIndex >= opts.mediaCount) {
      return { ok: false, error: "mediaIndex tag menunjuk foto yang tidak ada." };
    }
    if (!isFraction(entry.x) || !isFraction(entry.y)) {
      return { ok: false, error: "Koordinat tag harus di rentang 0-1." };
    }
    tags.push({ userId, mediaIndex, x: entry.x, y: entry.y });
  }
  return { ok: true, tags };
}

/**
 * Konversi hasil parseTaggedUsersInput jadi data createMany FeedPostTaggedUser
 * utk jalur EDIT (PATCH). mediaIndex input dipetakan ke mediaId nyata via
 * orderedMediaIds (urutan sortOrder asc). Video: mediaId/x/y null semua.
 */
export function buildTaggedUserRows(
  tags: TaggedUserInput[],
  feedPostId: string,
  orderedMediaIds: readonly string[],
  prevHiddenByUserId?: ReadonlyMap<string, boolean>,
): Array<{
  feedPostId: string;
  taggedUserId: string;
  mediaId: string | null;
  x: number | null;
  y: number | null;
  hidden: boolean;
}> {
  return tags.map((tag) => ({
    feedPostId,
    taggedUserId: tag.userId,
    mediaId: tag.mediaIndex != null ? orderedMediaIds[tag.mediaIndex] ?? null : null,
    x: tag.x,
    y: tag.y,
    // Full-replace (PATCH edit) tidak boleh menimpa flag privasi "hidden"
    // yang di-set tagged user sendiri via PATCH .../tags/me (Spec B
    // self-hide) — carry forward nilai lama kalau user itu masih di-tag,
    // default false untuk user yang baru ditambahkan.
    hidden: prevHiddenByUserId?.get(tag.userId) ?? false,
  }));
}

export type TaggedUserRow = {
  mediaId: string | null;
  x: number | null;
  y: number | null;
  hidden: boolean;
  taggedUser: {
    id: string;
    username: string | null;
    name: string | null;
    role: string;
    profilePhotoUrl: string | null;
  };
};

export type SerializedTaggedUser = {
  userId: string;
  username: string | null;
  name: string;
  profilePhotoUrl: string | null;
  mediaId: string | null;
  mediaIndex: number | null;
  x: number | null;
  y: number | null;
};

/**
 * Ready-transition notif fix (final review Spec B) — re-derive daftar
 * recipient userId dari baris FeedTaggedUser TERSIMPAN di DB (bukan dari
 * body request provisioning yang sudah basi). Dedupe saja; self-filter
 * (actor tidak dinotif ke diri sendiri) tetap tanggung jawab
 * sendTaggedUserNotifications (lib/feed/activity-notifications.ts) supaya
 * tidak dobel logic. Dipakai oleh notifyTaggedUsersOnVideoReady.
 */
export function taggedUserIdsFromRows(
  rows: ReadonlyArray<{ taggedUserId: string }>,
): string[] {
  return [...new Set(rows.map((row) => row.taggedUserId))];
}

/**
 * Viewer self-hide state (final review Spec B fix) — "viewerTagHidden" pada
 * level POST (bukan per-tag) merepresentasikan "apakah tag milik VIEWER YANG
 * SEDANG REQUEST ini disembunyikan", null kalau viewer tidak login atau tidak
 * ditandai di post ini. TIDAK PERNAH membocorkan status hidden tag milik user
 * lain — hanya baris yang cocok dengan viewerUserId yang pernah dibaca.
 * Tanpa field ini, sheet Opsi Tag selalu mulai dari `false` (session-local
 * saja) sehingga "un-hide" tidak bisa dijangkau lagi setelah app restart.
 */
export function resolveViewerTagHidden(
  rows: ReadonlyArray<Pick<TaggedUserRow, "hidden"> & { taggedUser: { id: string } }>,
  viewerUserId: string | null | undefined,
): boolean | null {
  if (!viewerUserId) return null;
  const own = rows.find((row) => row.taggedUser.id === viewerUserId);
  return own ? own.hidden : null;
}

/**
 * Shape response taggedUsers[] untuk semua endpoint post. Identitas akun
 * official WAJIB di-brand-kan (brand-user.ts) — nama/foto asli pemilik
 * tidak boleh bocor.
 */
export function serializeTaggedUsers(
  rows: TaggedUserRow[],
  mediaIdToIndex: Map<string, number>,
): SerializedTaggedUser[] {
  return rows.map((row) => ({
    userId: row.taggedUser.id,
    username: row.taggedUser.username,
    name: brandDisplayName(row.taggedUser.role, row.taggedUser.name),
    profilePhotoUrl: brandPhotoUrl(row.taggedUser.role, row.taggedUser.profilePhotoUrl),
    mediaId: row.mediaId,
    mediaIndex: row.mediaId != null ? mediaIdToIndex.get(row.mediaId) ?? null : null,
    x: row.x,
    y: row.y,
  }));
}

/**
 * Select fragment standar untuk relasi taggedUsers di query post.
 * hidden ikut di-select supaya serializer/route bisa filter kalau perlu.
 */
/**
 * Validasi body PATCH self-service tag ("Sembunyikan/Tampilkan dari
 * profil saya"). Hanya menerima { hidden: boolean }.
 */
/**
 * Where-clause "caller owns row" untuk self-service tag/me (DELETE+PATCH).
 * taggedUserId WAJIB berasal dari session (sessionUserId), tidak pernah
 * dari body/params — helper ini jadi satu-satunya sumber kebenaran supaya
 * properti keamanan ini terkunci & bisa di-unit-test.
 */
export function buildMyTagWhere(postId: string, sessionUserId: string) {
  return { feedPostId: postId, taggedUserId: sessionUserId };
}

export function parseHiddenBody(
  raw: unknown,
): { ok: true; hidden: boolean } | { ok: false; error: string } {
  if (typeof raw === "object" && raw !== null) {
    const hidden = (raw as Record<string, unknown>).hidden;
    if (typeof hidden === "boolean") return { ok: true, hidden };
  }
  return { ok: false, error: "Body harus {hidden: boolean}." };
}

export const TAGGED_USERS_SELECT = {
  orderBy: { createdAt: "asc" as const },
  select: {
    mediaId: true,
    x: true,
    y: true,
    hidden: true,
    taggedUser: {
      select: {
        id: true,
        username: true,
        name: true,
        role: true,
        profilePhotoUrl: true,
      },
    },
  },
} as const;
