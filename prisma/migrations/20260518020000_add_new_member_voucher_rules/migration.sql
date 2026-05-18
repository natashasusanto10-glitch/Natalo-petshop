CREATE TYPE "VoucherTargetUser" AS ENUM ('ALL_MEMBERS', 'NEW_MEMBER');

ALTER TABLE "Voucher"
ADD COLUMN "maxDiscountAmount" INTEGER,
ADD COLUMN "targetUser" "VoucherTargetUser" NOT NULL DEFAULT 'ALL_MEMBERS',
ADD COLUMN "newMemberMaxAccountAgeDays" INTEGER,
ADD COLUMN "newMemberRequireNoSuccessfulOrder" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "usageLimitPerUser" INTEGER NOT NULL DEFAULT 1;

CREATE INDEX "Voucher_targetUser_idx" ON "Voucher"("targetUser");
