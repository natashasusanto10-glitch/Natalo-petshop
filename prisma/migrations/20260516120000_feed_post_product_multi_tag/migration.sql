-- Shop the Look — many-to-many join FeedPost ↔ Product (up to 3 per post).
-- FeedPost.productId tetap dipertahankan untuk backward-compat (primary
-- product display + legacy posts). Backfill di akhir copy productId
-- existing ke FeedPostProduct sebagai row dengan position=0.

-- CreateTable
CREATE TABLE "FeedPostProduct" (
    "id" TEXT NOT NULL,
    "feedPostId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedPostProduct_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "FeedPostProduct_feedPostId_productId_key" ON "FeedPostProduct"("feedPostId", "productId");

-- CreateIndex
CREATE INDEX "FeedPostProduct_productId_idx" ON "FeedPostProduct"("productId");

-- CreateIndex
CREATE INDEX "FeedPostProduct_feedPostId_position_idx" ON "FeedPostProduct"("feedPostId", "position");

-- AddForeignKey
ALTER TABLE "FeedPostProduct" ADD CONSTRAINT "FeedPostProduct_feedPostId_fkey" FOREIGN KEY ("feedPostId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeedPostProduct" ADD CONSTRAINT "FeedPostProduct_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill: setiap FeedPost.productId existing → row di FeedPostProduct
-- dengan position=0. Idempotent karena ON CONFLICT DO NOTHING. Pakai
-- gen_random_uuid()::text untuk id supaya kompatibel dengan cuid format
-- yang dipakai aplikasi (id field expects string).
INSERT INTO "FeedPostProduct" ("id", "feedPostId", "productId", "position", "createdAt")
SELECT
  gen_random_uuid()::text,
  "id",
  "productId",
  0,
  COALESCE("publishedAt", "createdAt")
FROM "FeedPost"
WHERE "productId" IS NOT NULL
ON CONFLICT ("feedPostId", "productId") DO NOTHING;
