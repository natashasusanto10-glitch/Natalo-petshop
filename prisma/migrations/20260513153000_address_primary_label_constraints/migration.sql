UPDATE "Address"
SET "label" = NULL
WHERE "label" IS NOT NULL
  AND "label" NOT IN ('Rumah', 'Kantor');

WITH ranked_primary AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      PARTITION BY "userId"
      ORDER BY "createdAt" DESC, "id" DESC
    ) AS row_number
  FROM "Address"
  WHERE "isMain" = TRUE
)
UPDATE "Address" AS address
SET "isMain" = FALSE
FROM ranked_primary
WHERE address."id" = ranked_primary."id"
  AND ranked_primary.row_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS "idx_one_primary_per_user"
ON "Address"("userId")
WHERE "isMain" = TRUE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'Address_label_rumah_kantor_check'
  ) THEN
    ALTER TABLE "Address"
      ADD CONSTRAINT "Address_label_rumah_kantor_check"
      CHECK ("label" IS NULL OR "label" IN ('Rumah', 'Kantor'));
  END IF;
END $$;
