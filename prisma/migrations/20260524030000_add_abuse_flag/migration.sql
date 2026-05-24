-- Voucher abuse detection — table untuk track flagged user yang
-- pola behavior-nya mencurigakan (burst claim, gmail alias, sama
-- shipping address). Di-populate oleh cron job.

CREATE TABLE "AbuseFlag" (
  "id"                TEXT NOT NULL,
  "userId"            TEXT NOT NULL,
  "ruleCode"          TEXT NOT NULL,
  "severity"          TEXT NOT NULL DEFAULT 'MEDIUM',
  "details"           JSONB,
  "status"            TEXT NOT NULL DEFAULT 'OPEN',
  "reviewedAt"        TIMESTAMP(3),
  "reviewedByAdminId" TEXT,
  "adminNote"         TEXT,
  "createdAt"         TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AbuseFlag_pkey" PRIMARY KEY ("id")
);

-- Filter open flags per user (untuk skip create duplicate flag yang
-- masih OPEN, dan untuk profile inspector "flag count").
CREATE INDEX "AbuseFlag_userId_status_idx" ON "AbuseFlag"("userId", "status");

-- Admin dashboard "review queue" — open + sort by severity DESC, then
-- newest first.
CREATE INDEX "AbuseFlag_status_severity_createdAt_idx"
  ON "AbuseFlag"("status", "severity", "createdAt" DESC);

-- Rule-specific drill-down (e.g. "show all BURST_VOUCHER_CLAIM").
CREATE INDEX "AbuseFlag_ruleCode_createdAt_idx"
  ON "AbuseFlag"("ruleCode", "createdAt" DESC);

-- Global timeline.
CREATE INDEX "AbuseFlag_createdAt_idx"
  ON "AbuseFlag"("createdAt" DESC);

ALTER TABLE "AbuseFlag"
  ADD CONSTRAINT "AbuseFlag_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "AbuseFlag"
  ADD CONSTRAINT "AbuseFlag_reviewedByAdminId_fkey"
  FOREIGN KEY ("reviewedByAdminId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
