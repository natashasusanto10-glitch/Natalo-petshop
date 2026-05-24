-- Add username + history table untuk fitur @mention IG/TikTok-style.
-- Foundation only (Fase 1) — DB column + reservation table. Endpoint
-- + UI di follow-up commit.

-- ─── User: tambah username + usernameUpdatedAt ───────────────────────
ALTER TABLE "User"
  ADD COLUMN "username" TEXT,
  ADD COLUMN "usernameUpdatedAt" TIMESTAMP(3);

-- Unique constraint case-insensitive. Postgres "CITEXT" extension
-- bisa dipakai tapi butuh extension install. Simpler: simpan
-- username SUDAH lowercase di application layer, lalu unique
-- constraint biasa cukup. Validation di lib/username.ts pastikan
-- input di-lowercase sebelum write.
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- ─── UsernameHistory: reservasi 30 hari handle lama ──────────────────
CREATE TABLE "UsernameHistory" (
  "id"            TEXT NOT NULL,
  "userId"        TEXT NOT NULL,
  "username"      TEXT NOT NULL,
  "reservedUntil" TIMESTAMP(3) NOT NULL,
  "createdAt"     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "UsernameHistory_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "UsernameHistory_username_idx" ON "UsernameHistory"("username");
CREATE INDEX "UsernameHistory_reservedUntil_idx" ON "UsernameHistory"("reservedUntil");
CREATE INDEX "UsernameHistory_userId_idx" ON "UsernameHistory"("userId");

ALTER TABLE "UsernameHistory"
  ADD CONSTRAINT "UsernameHistory_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
