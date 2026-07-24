-- Spec C follow-up (code review findings):
--
-- 1) Hashtag.name prefix search (lib/feed/hashtags.ts searchHashtags uses
--    `startsWith`) has no supporting index — Postgres would sequential-scan
--    as the table grows. text_pattern_ops supports LIKE 'prefix%' / startsWith
--    index scans without needing an extra extension (pg_trgm also works but
--    is unnecessary here since we only need prefix match, not fuzzy).
CREATE INDEX IF NOT EXISTS "Hashtag_name_prefix_idx"
  ON "Hashtag" (name text_pattern_ops);

-- 2) Hashtag page pagination (app/api/feed/hashtags/[name]/route.ts) orders
--    posts by recency. FeedPostHashtag only had a single-column index on
--    hashtagId — add a composite (hashtagId, createdAt DESC) so a query
--    driven off FeedPostHashtag directly (not just the `some` relation
--    filter on FeedPost) can use an index scan in sorted order.
CREATE INDEX IF NOT EXISTS "FeedPostHashtag_hashtagId_createdAt_idx"
  ON "FeedPostHashtag" ("hashtagId", "createdAt" DESC);
