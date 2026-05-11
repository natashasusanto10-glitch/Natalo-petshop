-- Tambah kolom targetUserId di Announcement untuk personal notification
-- (mis. order status update). Kalau NULL → broadcast (filter via segment).
-- Idempotent (IF NOT EXISTS) — aman di-apply di prod yg sudah punya.

ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "targetUserId" TEXT;
CREATE INDEX IF NOT EXISTS "Announcement_targetUserId_idx" ON "Announcement"("targetUserId");
