-- Audit log untuk semua admin action — refund, order status changes,
-- voucher edits, dll. Compliance + dispute resolution + rogue admin
-- detection.

CREATE TABLE "AdminActionLog" (
  "id"          TEXT NOT NULL,
  "actorUserId" TEXT NOT NULL,
  "action"      TEXT NOT NULL,
  "targetType"  TEXT NOT NULL,
  "targetId"    TEXT NOT NULL,
  "summary"     TEXT NOT NULL,
  "metadata"    JSONB,
  "ipAddress"   TEXT,
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "AdminActionLog_pkey" PRIMARY KEY ("id")
);

-- Filter by admin (e.g. "show all actions by admin X")
CREATE INDEX "AdminActionLog_actorUserId_createdAt_idx"
  ON "AdminActionLog"("actorUserId", "createdAt" DESC);

-- Lookup by target entity (e.g. "show all actions on order Y")
CREATE INDEX "AdminActionLog_targetType_targetId_idx"
  ON "AdminActionLog"("targetType", "targetId");

-- Filter by action type (e.g. "show all REFUND_ISSUED last 7 days")
CREATE INDEX "AdminActionLog_action_createdAt_idx"
  ON "AdminActionLog"("action", "createdAt" DESC);

-- Global timeline (e.g. "show all admin actions newest first")
CREATE INDEX "AdminActionLog_createdAt_idx"
  ON "AdminActionLog"("createdAt" DESC);

ALTER TABLE "AdminActionLog"
  ADD CONSTRAINT "AdminActionLog_actorUserId_fkey"
  FOREIGN KEY ("actorUserId") REFERENCES "User"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
