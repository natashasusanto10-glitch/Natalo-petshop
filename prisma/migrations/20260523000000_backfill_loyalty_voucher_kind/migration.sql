-- Backfill `kind` untuk voucher loyalty yang historis di-create tanpa
-- set kind. Bug: `/api/member/claim-voucher` lama tidak set kolom
-- `kind`, sehingga Prisma default ke `PRODUCT_DISCOUNT` walaupun
-- `type = 'LOYALTY_POINT_CLAIM'`. Akibatnya checkout slot resolver
-- match-by-kind gagal, dan user dapat error
-- "Voucher tidak bisa digunakan untuk slot ini" saat explicit
-- re-apply voucher reward poin setelah release.
--
-- Backfill: setiap voucher dengan `type = 'LOYALTY_POINT_CLAIM'`
-- harus punya `kind = 'LOYALTY_CLAIM'`. Aman untuk dijalankan
-- berulang (idempotent).
UPDATE "Voucher"
SET "kind" = 'LOYALTY_CLAIM'
WHERE "type" = 'LOYALTY_POINT_CLAIM'
  AND "kind" <> 'LOYALTY_CLAIM';

-- Defensive: voucher dengan visibility USER_OWNED + sourceType CUSTOMER
-- + userId yang masih punya kind salah (mis. row legacy tanpa `type`
-- field di-set). voucherTypeOf() helper return LOYALTY_POINT_CLAIM untuk
-- pattern ini, jadi konsisten dengan derive-from-type logic di
-- `app/api/checkout/recalculate/route.ts` (`effectiveKind`).
UPDATE "Voucher"
SET "kind" = 'LOYALTY_CLAIM'
WHERE "userId" IS NOT NULL
  AND "sourceType" = 'CUSTOMER'
  AND "visibility" = 'USER_OWNED'
  AND "kind" <> 'LOYALTY_CLAIM';
