-- Switch ke Opsi B (Shopee strict): lock birthDate IMMEDIATE saat user
-- pertama set, bukan menunggu voucher issued.
--
-- Untuk user EXISTING yang sudah set birthDate (tapi belum dapat voucher
-- jadi birthDateLockedAt masih NULL), backfill lock dengan approximation
-- timestamp. Pakai COALESCE(updatedAt, createdAt) — best-effort guess
-- kapan birthDate kemungkinan di-set (user yg pernah edit profile dengan
-- birthDate, updatedAt sudah refresh).
--
-- Catatan: ini "free pass" closing — user existing yg sudah punya
-- birthDate gak dapat kesempatan ralat sendiri lagi. Kalau ada user yang
-- complain, CS bisa override via /admin/birth-date-overrides.
--
-- User yang BELUM set birthDate (NULL) tetap UNLOCKED — saat mereka set
-- nanti via Flutter, API auto-lock (lihat app/api/member/profile/route.ts).

UPDATE "User"
SET "birthDateLockedAt" = COALESCE("updatedAt", "createdAt")
WHERE "birthDate" IS NOT NULL
  AND "birthDateLockedAt" IS NULL;
