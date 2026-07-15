import type { Prisma } from "@prisma/client";

export const COMMENT_SYNC_MAX_REMOVED_IDS = 500;
export const COMMENT_SYNC_MAX_CHANGED_COMMENTS = 500;

const COMMENT_SYNC_MAX_FUTURE_SKEW_MS = 60 * 1000;
const COMMENT_SYNC_MAX_CURSOR_LENGTH = 128;

export type FeedCommentSyncWindow = {
  requested: boolean;
  since: Date | null;
  resetRequired: boolean;
};

export type FeedCommentRemovalSync = {
  removedCommentIds: string[];
  resetRequired: boolean;
};

export type FeedCommentChangeSync = {
  rootCommentIds: string[];
  resetRequired: boolean;
};

type CommentSyncReadClient = Pick<
  Prisma.TransactionClient,
  "feedComment" | "feedCommentTombstone" | "$queryRaw"
>;

function parseSyncTime(raw: string): Date | null {
  if (raw.length === 0 || raw.length > COMMENT_SYNC_MAX_CURSOR_LENGTH) {
    return null;
  }

  const numeric = /^\d{10,13}$/.test(raw) ? Number(raw) : null;
  const milliseconds =
    numeric === null
      ? Date.parse(raw)
      : raw.length === 10
      ? numeric * 1000
      : numeric;
  if (!Number.isFinite(milliseconds)) return null;

  const parsed = new Date(milliseconds);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * Resolve an optional client watermark. Commit cursors and hard-delete
 * tombstones are retained indefinitely, so a valid old cursor remains safe
 * and must not force clients into a repeated reset loop. Invalid or future
 * cursors request one full reset and intentionally avoid a partial delta.
 */
export function resolveFeedCommentSyncWindow({
  syncCursor,
  syncTime,
  now,
  currentCursor,
}: {
  syncCursor?: string | null;
  syncTime?: string | null;
  now: Date;
  currentCursor?: Date | null;
}): FeedCommentSyncWindow {
  const raw = (syncCursor?.trim() || syncTime?.trim() || "").trim();
  if (!raw) {
    return { requested: false, since: null, resetRequired: false };
  }

  const nowMs = now.getTime();
  const parsed = parseSyncTime(raw);
  if (
    !parsed ||
    parsed.getTime() > nowMs + COMMENT_SYNC_MAX_FUTURE_SKEW_MS ||
    (currentCursor != null &&
      parsed.getTime() > currentCursor.getTime())
  ) {
    return {
      requested: true,
      since: null,
      resetRequired: true,
    };
  }

  return {
    requested: true,
    since: parsed,
    resetRequired: false,
  };
}

export function visibleFeedCommentWhere(
  postId: string
): Prisma.FeedCommentWhereInput {
  return {
    postId,
    isHidden: false,
    OR: [
      {
        parentCommentId: null,
        OR: [
          { deletedAt: null },
          {
            replies: {
              some: { isHidden: false, deletedAt: null },
            },
          },
        ],
      },
      {
        parentCommentId: { not: null },
        deletedAt: null,
        // A self-deleted parent remains as a placeholder. Moderation hide is
        // intentionally different and removes the whole conversation.
        parent: { isHidden: false },
      },
    ],
  };
}

/**
 * Rows represented by the public counter. A deleted parent placeholder is a
 * rendering anchor, not a real comment, while its still-visible replies keep
 * contributing to the count.
 */
export function countedFeedCommentWhere(
  postId: string
): Prisma.FeedCommentWhereInput {
  return {
    postId,
    isHidden: false,
    deletedAt: null,
    OR: [{ parentCommentId: null }, { parent: { isHidden: false } }],
  };
}

/** Top-level rows rendered by listFeedComments, including placeholders. */
export function visibleFeedCommentRootWhere(
  postId: string
): Prisma.FeedCommentWhereInput {
  return {
    postId,
    parentCommentId: null,
    isHidden: false,
    OR: [
      { deletedAt: null },
      {
        replies: {
          some: { isHidden: false, deletedAt: null },
        },
      },
    ],
  };
}

export async function readDatabaseClock(
  db: Pick<CommentSyncReadClient, "$queryRaw">
): Promise<Date> {
  const rows = await db.$queryRaw<Array<{ now: Date }>>`
    SELECT clock_timestamp() AS "now"
  `;
  return rows[0]?.now ?? new Date();
}

/**
 * A Repeatable Read response must never advance its client watermark beyond
 * the snapshot it actually observed. transaction_timestamp() is fixed at the
 * start of the transaction, unlike clock_timestamp() which can move past a
 * concurrent commit that is not visible to the transaction snapshot.
 */
export async function readDatabaseSnapshotClock(
  db: Pick<CommentSyncReadClient, "$queryRaw">
): Promise<Date> {
  const rows = await db.$queryRaw<Array<{ now: Date }>>`
    SELECT transaction_timestamp() AS "now"
  `;
  return rows[0]?.now ?? new Date(0);
}

/**
 * Find visible conversations changed since the client watermark. syncVersion
 * is assigned by a database trigger while holding the post row lock, so a
 * transaction that commits after a reader snapshot always has a greater
 * cursor even if its createdAt/updatedAt value is older. Replies map
 * back to their top-level parent because the public API returns one-level
 * threads. The bounded result is appended to the normal first page; overflow
 * asks the client to reset and paginate from the fresh head instead of silently
 * skipping changes outside that page.
 */
export async function findChangedFeedCommentRootIds({
  db,
  postId,
  since,
  until,
  maxChanges = COMMENT_SYNC_MAX_CHANGED_COMMENTS,
}: {
  db: Pick<CommentSyncReadClient, "feedComment">;
  postId: string;
  since: Date | null;
  until: Date;
  maxChanges?: number;
}): Promise<FeedCommentChangeSync> {
  if (!since || maxChanges <= 0 || since.getTime() > until.getTime()) {
    return { rootCommentIds: [], resetRequired: maxChanges <= 0 };
  }

  const changed = await db.feedComment.findMany({
    where: {
      AND: [
        visibleFeedCommentWhere(postId),
        {
          syncVersion: { gt: since, lte: until },
        },
      ],
    },
    orderBy: [{ syncVersion: "asc" }, { id: "asc" }],
    take: maxChanges + 1,
    select: { id: true, parentCommentId: true },
  });

  if (changed.length > maxChanges) {
    return { rootCommentIds: [], resetRequired: true };
  }

  const rootCommentIds = [
    ...new Set(changed.map((comment) => comment.parentCommentId ?? comment.id)),
  ];
  if (rootCommentIds.length === 0) {
    return { rootCommentIds: [], resetRequired: false };
  }

  // Cap the rows that listFeedComments will serialize, not merely the rows
  // that happened to change. One changed reply can otherwise pull an old
  // thread with thousands of replies into a polling response.
  const serializedRowCount = await db.feedComment.count({
    where: {
      AND: [
        visibleFeedCommentWhere(postId),
        {
          OR: [
            { id: { in: rootCommentIds } },
            { parentCommentId: { in: rootCommentIds } },
          ],
        },
      ],
    },
  });
  if (serializedRowCount > maxChanges) {
    return { rootCommentIds: [], resetRequired: true };
  }

  return {
    rootCommentIds,
    resetRequired: false,
  };
}

/**
 * Return only explicit tombstones. A removed top-level comment expands to its
 * reply IDs so clients never need to infer hidden children from page absence.
 */
export async function findRemovedFeedCommentIds({
  db,
  postId,
  since,
  until,
  maxIds = COMMENT_SYNC_MAX_REMOVED_IDS,
}: {
  db: Pick<CommentSyncReadClient, "feedComment" | "feedCommentTombstone">;
  postId: string;
  since: Date | null;
  until: Date;
  maxIds?: number;
}): Promise<FeedCommentRemovalSync> {
  if (!since || maxIds <= 0 || since.getTime() > until.getTime()) {
    return { removedCommentIds: [], resetRequired: maxIds <= 0 };
  }

  const changedRows = await db.feedComment.findMany({
    where: {
      AND: [
        { postId, syncVersion: { gt: since, lte: until } },
        {
          OR: [
            { isHidden: true },
            {
              parentCommentId: { not: null },
              deletedAt: { not: null },
            },
            {
              parentCommentId: null,
              deletedAt: { not: null },
              replies: {
                none: { isHidden: false, deletedAt: null },
              },
            },
          ],
        },
      ],
    },
    orderBy: [{ syncVersion: "asc" }, { id: "asc" }],
    take: maxIds + 1,
    select: { id: true, parentCommentId: true, syncVersion: true },
  });

  const tombstones = await db.feedCommentTombstone.findMany({
    where: {
      postId,
      syncVersion: { gt: since, lte: until },
    },
    orderBy: [{ syncVersion: "asc" }, { commentId: "asc" }],
    take: maxIds + 1,
    select: {
      commentId: true,
      parentCommentId: true,
      syncVersion: true,
    },
  });

  const changed = [
    ...changedRows.map((comment) => ({
      id: comment.id,
      parentCommentId: comment.parentCommentId,
      syncVersion: comment.syncVersion,
    })),
    ...tombstones.map((tombstone) => ({
      id: tombstone.commentId,
      parentCommentId: tombstone.parentCommentId,
      syncVersion: tombstone.syncVersion,
    })),
  ]
    .sort((left, right) => {
      const timeOrder =
        left.syncVersion.getTime() - right.syncVersion.getTime();
      return timeOrder !== 0 ? timeOrder : left.id.localeCompare(right.id);
    })
    .filter(
      (comment, index, all) =>
        all.findIndex((candidate) => candidate.id === comment.id) === index
    );

  const overflowedChanges = changed.length > maxIds;
  const boundedChanges = changed.slice(0, maxIds);
  const removedIds = new Set(boundedChanges.map((comment) => comment.id));
  if (overflowedChanges) {
    return {
      removedCommentIds: [...removedIds],
      resetRequired: true,
    };
  }

  // Deleting the last visible reply can collapse an already self-deleted
  // parent. The parent's own syncVersion is older, so derive that tombstone
  // from the changed reply in this window.
  const affectedParentIds = [
    ...new Set(
      boundedChanges
        .map((comment) => comment.parentCommentId)
        .filter((id): id is string => Boolean(id))
    ),
  ];
  if (affectedParentIds.length > 0) {
    const remainingForParents = Math.max(0, maxIds - removedIds.size);
    const collapsedParents = await db.feedComment.findMany({
      where: {
        id: { in: affectedParentIds },
        postId,
        parentCommentId: null,
        isHidden: false,
        deletedAt: { not: null },
        replies: { none: { isHidden: false, deletedAt: null } },
      },
      orderBy: { id: "asc" },
      take: remainingForParents + 1,
      select: { id: true },
    });
    if (collapsedParents.length > remainingForParents) {
      for (const parent of collapsedParents.slice(0, remainingForParents)) {
        removedIds.add(parent.id);
      }
      return {
        removedCommentIds: [...removedIds],
        resetRequired: true,
      };
    }
    for (const parent of collapsedParents) removedIds.add(parent.id);
  }

  const removedParentIds = [
    ...new Set([
      ...boundedChanges
        .filter((comment) => comment.parentCommentId === null)
        .map((comment) => comment.id),
      ...[...removedIds].filter((id) => affectedParentIds.includes(id)),
    ]),
  ];
  if (removedParentIds.length === 0) {
    return {
      removedCommentIds: [...removedIds],
      resetRequired: false,
    };
  }

  const remaining = Math.max(0, maxIds - removedIds.size);
  const replies = await db.feedComment.findMany({
    where: {
      postId,
      parentCommentId: { in: removedParentIds },
    },
    orderBy: { id: "asc" },
    take: remaining + 1,
    select: { id: true },
  });
  const overflowedReplies = replies.length > remaining;
  for (const reply of replies.slice(0, remaining)) {
    removedIds.add(reply.id);
  }

  return {
    removedCommentIds: [...removedIds],
    resetRequired: overflowedReplies,
  };
}
