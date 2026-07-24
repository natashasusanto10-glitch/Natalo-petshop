/**
 * Hashtag (Spec C) — SATU sumber aturan parsing, di-mirror persis di
 * flutter_app/lib/utils/mention_text.dart. Ubah di sini ⇒ ubah di sana.
 *
 * Boundary: '#' hanya valid di awal teks atau setelah whitespace —
 * "harga#promo" dan "natalo.com/#promo" BUKAN tag (spec §1).
 */
import { PUBLIC_FEED_POST_WHERE } from "./queries";

const HASHTAG_SOURCE = /(^|\s)#([a-z0-9_]+)/gi;

export const MAX_HASHTAGS_PER_POST = 5;
export const HASHTAG_LIMIT_MESSAGE = "Maksimal 5 hashtag per postingan.";

const MIN_NAME_LENGTH = 2;
const MAX_NAME_LENGTH = 50;

/** Nama kanonik: lowercase [a-z0-9_], panjang 2-50, tanpa '#'. */
export function isValidHashtagName(name: string): boolean {
  if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
    return false;
  }
  return /^[a-z0-9_]+$/.test(name);
}

/**
 * Extract hashtag dari teks caption: lowercase, dedup (sekali hitung),
 * urutan kemunculan pertama, filter panjang 2-50 (filter di fungsi, bukan
 * regex — pola sama extractMentionHandles di lib/feed/mentions.ts).
 */
export function extractHashtags(text: string): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const match of text.matchAll(HASHTAG_SOURCE)) {
    const name = match[2].toLowerCase();
    if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
      continue;
    }
    if (seen.has(name)) continue;
    seen.add(name);
    result.push(name);
  }
  return result;
}

/** Subset TransactionClient yang dipakai — injectable untuk unit test. */
export type HashtagTx = {
  hashtag: {
    upsert: (args: {
      where: { name: string };
      create: { name: string; postCount: number };
      update: { postCount: { increment: number } };
    }) => Promise<{ id: string }>;
    updateMany: (args: {
      where: { id: { in: string[] }; postCount: { gt: number } };
      data: { postCount: { decrement: number } };
    }) => Promise<unknown>;
  };
  feedPostHashtag: {
    createMany: (args: {
      data: { feedPostId: string; hashtagId: string }[];
    }) => Promise<unknown>;
    findMany: (args: {
      where: { feedPostId: string };
      select: { hashtagId: true };
    }) => Promise<{ hashtagId: string }[]>;
  };
};

/**
 * Panggil DI DALAM $transaction create post (foto & video — dua-duanya jalur
 * client DAN admin; tidak ada route create lain). captionText = gabungan
 * `${title} ${description ?? ""}` — sumber yang sama dengan gate mention.
 */
export async function syncPostHashtags(
  tx: HashtagTx,
  feedPostId: string,
  captionText: string,
): Promise<void> {
  const names = extractHashtags(captionText);
  if (names.length === 0) return;
  const rows: { feedPostId: string; hashtagId: string }[] = [];
  for (const name of names) {
    const tag = await tx.hashtag.upsert({
      where: { name },
      create: { name, postCount: 1 },
      update: { postCount: { increment: 1 } },
    });
    rows.push({ feedPostId, hashtagId: tag.id });
  }
  await tx.feedPostHashtag.createMany({ data: rows });
}

/**
 * HANYA untuk jalur HARD delete (admin ?hard=1). Soft delete (deletedAt)
 * TIDAK men-decrement — postCount memang aproksimatif (spec §1), halaman
 * hashtag ter-filter PUBLIC_FEED_POST_WHERE jadi tetap benar.
 * Panggil SEBELUM prisma.feedPost.delete (cascade menghapus junction-nya).
 */
export async function decrementHashtagCounts(
  tx: HashtagTx,
  feedPostId: string,
): Promise<void> {
  const rows = await tx.feedPostHashtag.findMany({
    where: { feedPostId },
    select: { hashtagId: true },
  });
  if (rows.length === 0) return;
  await tx.hashtag.updateMany({
    where: { id: { in: rows.map((r) => r.hashtagId) }, postCount: { gt: 0 } },
    data: { postCount: { decrement: 1 } },
  });
}

/** Where-clause halaman hashtag: visibilitas feed penuh + relasi tag. */
export function hashtagPostsWhere(name: string) {
  return {
    ...PUBLIC_FEED_POST_WHERE,
    hashtags: { some: { hashtag: { name } } },
  };
}

export type HashtagSearchDb = {
  hashtag: {
    findMany: (args: {
      where: { name: { startsWith: string } };
      orderBy: { postCount: "desc" };
      take: number;
      select: { name: true; postCount: true };
    }) => Promise<{ name: string; postCount: number }[]>;
  };
};

/** Autocomplete: prefix match lowercase, urut postCount desc, maks 8. */
export async function searchHashtags(
  db: HashtagSearchDb,
  q: string,
): Promise<{ name: string; postCount: number }[]> {
  const prefix = q.trim().toLowerCase();
  if (prefix.length === 0) return [];
  return db.hashtag.findMany({
    where: { name: { startsWith: prefix } },
    orderBy: { postCount: "desc" },
    take: 8,
    select: { name: true, postCount: true },
  });
}
