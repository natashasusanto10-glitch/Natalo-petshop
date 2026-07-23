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
