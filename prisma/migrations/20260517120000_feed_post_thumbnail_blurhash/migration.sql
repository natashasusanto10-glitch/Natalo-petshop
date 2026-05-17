-- Tambah kolom thumbnailBlurhash untuk LQIP placeholder. Generated
-- server-side di Bunny webhook saat thumbnail tersedia, di-decode di
-- client jadi canvas 32x32 sebagai placeholder instan sebelum image
-- real load. Backfill untuk post existing dilakukan lazy via cron
-- (atau saat user view post pertama kali, server background-fill).

ALTER TABLE "FeedPost" ADD COLUMN "thumbnailBlurhash" TEXT;
