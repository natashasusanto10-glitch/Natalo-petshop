-- Popup promo bergambar saat app cold start (gaya Shopee: satu gambar
-- kreatif penuh + tombol X). Menggantikan konten hardcoded LaunchPromoGate
-- Flutter — admin upload gambar + link tujuan, app fetch via
-- GET /api/launch-popup.
--
-- IDEMPOTEN (IF NOT EXISTS) mengikuti konvensi migration repo ini supaya
-- `prisma migrate deploy` aman kalau sebagian environment pernah kena
-- `db push` (pelajaran insiden kolom video Product).

CREATE TABLE IF NOT EXISTS "LaunchPopup" (
    "id" TEXT NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "imageAlt" TEXT NOT NULL DEFAULT '',
    "linkType" TEXT NOT NULL DEFAULT 'none',
    "linkValue" TEXT,
    "audience" TEXT NOT NULL DEFAULT 'member',
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LaunchPopup_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "LaunchPopup_isActive_startsAt_endsAt_idx"
    ON "LaunchPopup"("isActive", "startsAt", "endsAt");
