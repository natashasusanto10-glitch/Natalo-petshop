-- Admin-managed hero banner slider untuk Home app customer.
-- Menggantikan data/heroSlides.ts hardcoded (tetap jadi fallback kalau kosong).

CREATE TABLE "HomeBanner" (
  "id" TEXT NOT NULL,
  "imageUrl" TEXT NOT NULL,
  "imageAlt" TEXT NOT NULL DEFAULT '',
  "linkType" TEXT NOT NULL DEFAULT 'none',
  "linkValue" TEXT,
  "position" INTEGER NOT NULL DEFAULT 0,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "HomeBanner_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "HomeBanner_isActive_position_idx"
  ON "HomeBanner"("isActive", "position");
