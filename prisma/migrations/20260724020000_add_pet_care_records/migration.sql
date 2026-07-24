ALTER TABLE "Pet" ADD COLUMN IF NOT EXISTS "sterilized" BOOLEAN;
ALTER TABLE "Pet" ADD COLUMN IF NOT EXISTS "allergy" TEXT;
ALTER TABLE "Pet" ADD COLUMN IF NOT EXISTS "healthNote" TEXT;

CREATE TABLE IF NOT EXISTS "PetCareRecord" (
    "id" TEXT NOT NULL,
    "petId" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "doneAt" TIMESTAMP(3) NOT NULL,
    "note" TEXT,
    "nextDueAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PetCareRecord_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "PetCareRecord_petId_doneAt_idx" ON "PetCareRecord"("petId", "doneAt");

DO $$ BEGIN
    ALTER TABLE "PetCareRecord" ADD CONSTRAINT "PetCareRecord_petId_fkey" FOREIGN KEY ("petId") REFERENCES "Pet"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
