-- Kolom identitas aktor terstruktur untuk notifikasi sosial (komentar,
-- mention, like tunggal, follow). Memungkinkan app menampilkan foto + nama
-- aktor di kiri baris notifikasi, brand-safe (admin → null avatar + nama
-- brand, di-guard di layer aplikasi via lib/social/brand-user.ts).
-- Nullable: baris lama & notif non-aktor (sistem/pesanan/promo) tetap null.

ALTER TABLE "Announcement"
ADD COLUMN IF NOT EXISTS "actorAvatarUrl" TEXT,
ADD COLUMN IF NOT EXISTS "actorName" TEXT;
