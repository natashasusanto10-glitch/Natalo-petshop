-- Incremental comment sync used to rely on updatedAt plus a one-second
-- overlap. That can miss a transaction which commits after a reader snapshot
-- while carrying an older application timestamp. A per-post logical cursor is
-- serialized on the FeedPost row so cursor order now matches commit order.

ALTER TABLE "FeedPost"
ADD COLUMN "commentSyncCursor" TIMESTAMP(3) NOT NULL
DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC');

ALTER TABLE "FeedComment"
ADD COLUMN "syncVersion" TIMESTAMP(3) NOT NULL
DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC');

-- Hard deletes cannot be represented on FeedComment itself. Keep a durable,
-- FK-free removal ledger so User cascades can still reach clients polling a
-- surviving post. FeedPost hard deletes clean their own ledger rows below.
CREATE TABLE "FeedCommentTombstone" (
  "commentId" TEXT NOT NULL,
  "postId" TEXT NOT NULL,
  "parentCommentId" TEXT,
  "syncVersion" TIMESTAMP(3) NOT NULL,
  "removedAt" TIMESTAMP(3) NOT NULL
    DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),

  CONSTRAINT "FeedCommentTombstone_pkey" PRIMARY KEY ("commentId")
);

-- Force existing clients through one safe refresh after deployment. Every
-- legacy comment receives the migration cursor, which is newer than cursors
-- issued before this migration.
UPDATE "FeedPost"
SET "commentSyncCursor" = GREATEST(
  "commentSyncCursor",
  CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
);

UPDATE "FeedComment" AS comment
SET "syncVersion" = post."commentSyncCursor"
FROM "FeedPost" AS post
WHERE post."id" = comment."postId";

-- Reconcile denormalized counters with the new placeholder contract. A
-- self-deleted parent is not counted, but visible replies below it are.
UPDATE "FeedPost" AS post
SET "commentCount" = (
  SELECT COUNT(*)::INTEGER
  FROM "FeedComment" AS comment
  LEFT JOIN "FeedComment" AS parent
    ON parent."id" = comment."parentCommentId"
  WHERE comment."postId" = post."id"
    AND comment."isHidden" = FALSE
    AND comment."deletedAt" IS NULL
    AND (
      comment."parentCommentId" IS NULL
      OR parent."isHidden" = FALSE
    )
);

CREATE INDEX "FeedComment_postId_syncVersion_idx"
ON "FeedComment"("postId", "syncVersion");

CREATE INDEX "FeedCommentTombstone_postId_syncVersion_idx"
ON "FeedCommentTombstone"("postId", "syncVersion");

CREATE OR REPLACE FUNCTION "assignFeedCommentSyncVersion"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  next_cursor TIMESTAMP(3);
BEGIN
  -- UPDATE obtains a row lock held until transaction end. Concurrent writers
  -- for one post therefore receive cursors in commit order. The +1ms floor is
  -- deliberate because Flutter/JSON cursors have millisecond precision.
  UPDATE "FeedPost"
  SET "commentSyncCursor" = GREATEST(
    "commentSyncCursor" + INTERVAL '1 millisecond',
    clock_timestamp() AT TIME ZONE 'UTC'
  )
  WHERE "id" = NEW."postId"
  RETURNING "commentSyncCursor" INTO next_cursor;

  IF next_cursor IS NULL THEN
    RAISE EXCEPTION 'FeedPost % not found while assigning comment sync cursor',
      NEW."postId";
  END IF;

  NEW."syncVersion" = next_cursor;
  RETURN NEW;
END;
$$;

CREATE TRIGGER "FeedComment_assign_sync_version"
BEFORE INSERT OR UPDATE ON "FeedComment"
FOR EACH ROW
EXECUTE FUNCTION "assignFeedCommentSyncVersion"();

CREATE OR REPLACE FUNCTION "recordFeedCommentTombstone"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  next_cursor TIMESTAMP(3);
BEGIN
  -- A User cascade leaves the post alive, so this row lock serializes the
  -- tombstone with every other comment mutation on that post. During a
  -- FeedPost cascade the parent row is already invisible to UPDATE; in that
  -- case there is no post clients can poll and no tombstone is necessary.
  UPDATE "FeedPost"
  SET "commentSyncCursor" = GREATEST(
    "commentSyncCursor" + INTERVAL '1 millisecond',
    clock_timestamp() AT TIME ZONE 'UTC'
  )
  WHERE "id" = OLD."postId"
  RETURNING "commentSyncCursor" INTO next_cursor;

  IF next_cursor IS NULL THEN
    RETURN OLD;
  END IF;

  INSERT INTO "FeedCommentTombstone" (
    "commentId",
    "postId",
    "parentCommentId",
    "syncVersion",
    "removedAt"
  ) VALUES (
    OLD."id",
    OLD."postId",
    OLD."parentCommentId",
    next_cursor,
    clock_timestamp() AT TIME ZONE 'UTC'
  )
  ON CONFLICT ("commentId") DO UPDATE
  SET "postId" = EXCLUDED."postId",
      "parentCommentId" = EXCLUDED."parentCommentId",
      "syncVersion" = EXCLUDED."syncVersion",
      "removedAt" = EXCLUDED."removedAt";

  RETURN OLD;
END;
$$;

CREATE TRIGGER "FeedComment_record_tombstone"
BEFORE DELETE ON "FeedComment"
FOR EACH ROW
EXECUTE FUNCTION "recordFeedCommentTombstone"();

CREATE OR REPLACE FUNCTION "cleanupFeedCommentTombstones"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM "FeedCommentTombstone" WHERE "postId" = OLD."id";
  RETURN OLD;
END;
$$;

CREATE TRIGGER "FeedPost_cleanup_comment_tombstones"
AFTER DELETE ON "FeedPost"
FOR EACH ROW
EXECUTE FUNCTION "cleanupFeedCommentTombstones"();
