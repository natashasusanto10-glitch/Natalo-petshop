-- Structured metadata for Feed notifications in Notification Center.
ALTER TABLE "Announcement"
ADD COLUMN "source" TEXT,
ADD COLUMN "eventType" TEXT,
ADD COLUMN "feedPostId" TEXT,
ADD COLUMN "thumbnailUrl" TEXT,
ADD COLUMN "feedStatus" TEXT;

CREATE INDEX "Announcement_source_idx" ON "Announcement"("source");
CREATE INDEX "Announcement_eventType_idx" ON "Announcement"("eventType");
CREATE INDEX "Announcement_feedPostId_idx" ON "Announcement"("feedPostId");
