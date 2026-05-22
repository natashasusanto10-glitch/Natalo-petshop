-- Add User.bio column — short bio text (max 150 char enforced di app layer).
-- Nullable: backfill OK, user lama tetap valid.
ALTER TABLE "User" ADD COLUMN "bio" TEXT;
