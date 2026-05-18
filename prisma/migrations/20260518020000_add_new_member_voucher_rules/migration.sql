-- Idempotent — maxDiscountAmount + usageLimitPerUser sudah ditambah
-- migration 20260517153000_voucher_slots_and_usage. targetUser +
-- newMember columns adalah field baru.

-- CREATE TYPE via DO block (CREATE TYPE tidak support IF NOT EXISTS)
DO $$ BEGIN
  CREATE TYPE "VoucherTargetUser" AS ENUM ('ALL_MEMBERS', 'NEW_MEMBER');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- ADD COLUMN IF NOT EXISTS supaya duplicate column skip
ALTER TABLE "Voucher"
ADD COLUMN IF NOT EXISTS "maxDiscountAmount" INTEGER,
ADD COLUMN IF NOT EXISTS "targetUser" "VoucherTargetUser" NOT NULL DEFAULT 'ALL_MEMBERS',
ADD COLUMN IF NOT EXISTS "newMemberMaxAccountAgeDays" INTEGER,
ADD COLUMN IF NOT EXISTS "newMemberRequireNoSuccessfulOrder" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "usageLimitPerUser" INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS "Voucher_targetUser_idx" ON "Voucher"("targetUser");
