-- Anti-abuse: lock birthDate setelah user dapat voucher ultah pertama.
-- Setelah field ini != null, API profile reject perubahan birthDate.

-- AlterTable
ALTER TABLE "User" ADD COLUMN "birthDateLockedAt" TIMESTAMP(3);

-- Backfill: untuk user yang SUDAH pernah dapat voucher (birthdayVoucherYear
-- != null), lock juga birthDate-nya secara retroactive supaya konsisten.
-- Pakai updatedAt sebagai best-effort approximation kapan voucher di-issue
-- (user yg pernah dapat voucher biasanya udah berhenti edit profile).
UPDATE "User"
SET "birthDateLockedAt" = "updatedAt"
WHERE "birthdayVoucherYear" IS NOT NULL;
