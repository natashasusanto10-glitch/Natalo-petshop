-- Search query logging table — feeds "Pencarian populer" auto-generate.
-- Append-only writes. Indexed by createdAt for time-window queries, and by
-- (keyword, createdAt) for keyword aggregation in last-N-days lookups.

CREATE TABLE "SearchLog" (
    "id" TEXT NOT NULL,
    "keyword" TEXT NOT NULL,
    "userId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SearchLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SearchLog_createdAt_idx" ON "SearchLog"("createdAt");
CREATE INDEX "SearchLog_keyword_createdAt_idx" ON "SearchLog"("keyword", "createdAt");
