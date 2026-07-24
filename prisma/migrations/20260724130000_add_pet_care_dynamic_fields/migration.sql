-- Perawatan form dinamis per kategori + rekomendasi obat cacing/kutu.
-- Semua kolom baru nullable/opsional dengan default — tidak butuh backfill,
-- record/produk lama tetap valid tanpa perubahan.

ALTER TABLE "Product"
ADD COLUMN IF NOT EXISTS "careCategory" TEXT,
ADD COLUMN IF NOT EXISTS "targetSpecies" TEXT[] NOT NULL DEFAULT '{}',
ADD COLUMN IF NOT EXISTS "dosageRules" JSONB;

ALTER TABLE "Pet"
ADD COLUMN IF NOT EXISTS "weightKg" DOUBLE PRECISION;

ALTER TABLE "PetCareRecord"
ADD COLUMN IF NOT EXISTS "productId" TEXT,
ADD COLUMN IF NOT EXISTS "brandText" TEXT,
ADD COLUMN IF NOT EXISTS "dosageNote" TEXT,
ADD COLUMN IF NOT EXISTS "weightKg" DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS "place" TEXT,
ADD COLUMN IF NOT EXISTS "vaccineName" TEXT,
ADD COLUMN IF NOT EXISTS "complaint" TEXT;

CREATE TABLE IF NOT EXISTS "PetWeightLog" (
    "id" TEXT NOT NULL,
    "petId" TEXT NOT NULL,
    "weightKg" DOUBLE PRECISION NOT NULL,
    "recordedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "careRecordId" TEXT,

    CONSTRAINT "PetWeightLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "PetWeightLog_petId_recordedAt_idx" ON "PetWeightLog"("petId", "recordedAt");

DO $$ BEGIN
    ALTER TABLE "PetWeightLog" ADD CONSTRAINT "PetWeightLog_petId_fkey" FOREIGN KEY ("petId") REFERENCES "Pet"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
