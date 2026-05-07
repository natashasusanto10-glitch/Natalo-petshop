-- Create ProductVariantOption junction table (replaces dropped VariantOptionOnVariant)
CREATE TABLE IF NOT EXISTS "ProductVariantOption" (
  "id"        TEXT NOT NULL,
  "variantId" TEXT NOT NULL,
  "optionId"  TEXT NOT NULL,
  CONSTRAINT "ProductVariantOption_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ProductVariantOption_variantId_optionId_key"
  ON "ProductVariantOption"("variantId", "optionId");

ALTER TABLE "ProductVariantOption"
  ADD CONSTRAINT "ProductVariantOption_variantId_fkey"
  FOREIGN KEY ("variantId") REFERENCES "ProductVariant"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ProductVariantOption"
  ADD CONSTRAINT "ProductVariantOption_optionId_fkey"
  FOREIGN KEY ("optionId") REFERENCES "VariantOption"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
