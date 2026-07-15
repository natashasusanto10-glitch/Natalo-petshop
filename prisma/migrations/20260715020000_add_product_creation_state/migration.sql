ALTER TABLE "Product"
  ADD COLUMN "creationState" TEXT NOT NULL DEFAULT 'ready';

CREATE INDEX "Product_creationState_isActive_idx"
  ON "Product"("creationState", "isActive");
